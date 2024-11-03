const std = @import("std");
const log = std.log;

// Import LabJack LJM and Paho MQTT C libraries
const c = @cImport({
    @cInclude("/usr/local/include/LabJackM.h");
    @cInclude("/usr/local/include/MQTTClient.h");
});

// Define custom errors
const LJMError = error{LJMError};
const MQTTConnectionFailed = error{MQTTConnectionFailed};
const MQTTSubscriptionFailed = error{MQTTSubscriptionFailed};
const InvalidValveName = error{InvalidValveName};

// Application State
const AppState = struct {
    labjack_handle: i32,
    mqtt_client: c.MQTTClient,
    valve_controller: ValveController,
    pressure_sensor: PressureSensor,
    thermocouple_sensor: ThermocoupleSensor,
    load_cell_sensor: LoadCellSensor,
    allocator: *std.mem.Allocator,
};

// Check LJM Error

fn checkLJMError(err: i32 , context: []const u8) !void {
    if (err != 0) {
        const error_string = try c.LJM_ErrorToString(err , &context);
        log.err("LJM Error in {s}: {s}", .{ context, error_string });
        return LJMError;
    }
}

// Valve Controller
const ValveController = struct {
    handle: i32,

    pub fn init(handle: i32) ValveController {
        return ValveController{ .handle = handle };
    }

    pub fn actuate(self: *ValveController, valve_name: []const u8, state: []const u8) !void {
        // Map valve names to Modbus addresses or names
        const address = if (std.mem.eql(u8, valve_name, "main_valve")) "FIO0" else if (std.mem.eql(u8, valve_name, "pilot_valve")) "FIO1" else return InvalidValveName;

        // Convert state to numerical value
        const state_value = if (std.mem.eql(u8, state, "open")) 1 else 0;

        // Write to the digital output
        const err = c.LJM_eWriteName(self.handle, address, state_value);
        try checkLJMError(err, "Actuating valve");
        log.info("Actuated valve '{s}' to state '{s}'", .{ valve_name, state });
    }
};

// Pressure Sensor
const PressureSensor = struct {
    handle: i32,

    pub fn init(handle: i32) PressureSensor {
        return PressureSensor{ .handle = handle };
    }

    pub fn read(self: *PressureSensor) !f64 {
        var pressure: f64 = 0;
        const err = c.LJM_eReadName(self.handle, "AIN0", &pressure); // Read from analog input AIN0
        try checkLJMError(err, "Reading pressure sensor");
        return pressure;
    }
};

// Thermocouple Sensor
const ThermocoupleSensor = struct {
    handle: i32,

    pub fn init(handle: i32) ThermocoupleSensor {
        return ThermocoupleSensor{ .handle = handle };
    }

    pub fn read(self: *ThermocoupleSensor) !f64 {
        var temperature: f64 = 0;
        const err = c.LJM_eReadName(self.handle, "TEMPERATURE_DEVICE_K", &temperature); // Read temperature
        try checkLJMError(err, "Reading thermocouple sensor");
        return temperature;
    }
};

// Load Cell Sensor
const LoadCellSensor = struct {
    handle: i32,

    pub fn init(handle: i32) LoadCellSensor {
        return LoadCellSensor{ .handle = handle };
    }

    pub fn read(self: *LoadCellSensor) !f64 {
        var load_cell_value: f64 = 0;
        const err = c.LJM_eReadName(self.handle, "AIN1", &load_cell_value); // Read from analog input AIN1
        try checkLJMError(err, "Reading load cell sensor");
        return load_cell_value;
    }
};

// MQTT Topics
const Topics = struct {
    valve_command: []const u8 = "labjack/valve/command",
    pressure_data: []const u8 = "labjack/pressure/data",
    temperature_data: []const u8 = "labjack/temperature/data",
    load_cell_data: []const u8 = "labjack/load_cell/data",
    // Add other topics as needed
};

// Main Function
pub fn main() !void {
    // Initialize the general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer gpa.deinit();

    const allocator = gpa.allocator();
    // Get LabJack IP from environment variable
    // const env_ip = std.os.getenv("LABJACK_IP");
    const labjack_ip = "192.168.1.100";

    // Initialize LabJack connection over network
    var handle: i32 = 0;
    const device_type: i32 = 7; // T7 device
    const connection_type: i32 = c.LJM_ctTCP; // TCP connection
    const identifier = labjack_ip;
    const err = c.LJM_Open(device_type, connection_type, identifier, &handle);
    try checkLJMError(err, "Opening LabJack device over network");
    defer c.LJM_Close(handle);

    // Initialize Controllers and Sensors
    const valve_controller = ValveController.init(handle);
    const pressure_sensor = PressureSensor.init(handle);
    const thermocouple_sensor = ThermocoupleSensor.init(handle);
    const load_cell_sensor = LoadCellSensor.init(handle);

    // Initialize MQTT Client
    var mqtt_client: c.MQTTClient = undefined;
    const address = "tcp://mqtt_broker:1883";
    const client_id = "labjack_client";

    // Create MQTT Client
    c.MQTTClient_create(&mqtt_client, address, client_id, c.MQTTCLIENT_PERSISTENCE_NONE, null);

    // Set Connection Options
    var conn_opts: c.MQTTClient_connectOptions = c.MQTTClient_connectOptions{
        .struct_id = "MQTC",
        .struct_version = 0,
        .keepAliveInterval = 60,
        .cleansession = 1,
        .reliable = 0,
        .username = null,
        .password = null,
    };

    // Connect to MQTT Broker
    const rc = c.MQTTClient_connect(mqtt_client, &conn_opts);
    if (rc != c.MQTTCLIENT_SUCCESS) {
        log.err("Failed to connect to MQTT broker, return code {d}", .{rc});
        return MQTTConnectionFailed;
    }
    defer c.MQTTClient_disconnect(mqtt_client, 10000);
    defer c.MQTTClient_destroy(&mqtt_client);

    log.info("Connected to MQTT broker at {s}", .{address});

    // Set Application State
    var app_state = AppState{
        .labjack_handle = handle,
        .mqtt_client = mqtt_client,
        .valve_controller = valve_controller,
        .pressure_sensor = pressure_sensor,
        .thermocouple_sensor = thermocouple_sensor,
        .load_cell_sensor = load_cell_sensor,
        .allocator = allocator,
    };

    // Subscribe to Valve Command Topic
    const topics = &[_][]const u8{Topics.valve_command};
    const qos = &[_]c.int{0};
    const sub_rc = c.MQTTClient_subscribeMany(mqtt_client, 1, topics, qos);
    if (sub_rc != c.MQTTCLIENT_SUCCESS) {
        log.err("Failed to subscribe to topics, return code {d}", .{sub_rc});
        return MQTTSubscriptionFailed;
    }
    log.info("Subscribed to topic: {s}", .{Topics.valve_command});

    // Start Sensor Data Publishing Tasks
    var pressure_task = try std.Thread.spawn(publishPressureData, &app_state);
    var temperature_task = try std.Thread.spawn(publishTemperatureData, &app_state);
    var load_cell_task = try std.Thread.spawn(publishLoadCellData, &app_state);

    defer {
        _ = pressure_task.wait();
        _ = temperature_task.wait();
        _ = load_cell_task.wait();
    }

    // Main Event Loop
    while (true) {
        // Receive MQTT Messages
        var msg: *c.MQTTClient_message = null;
        var topic_name: [*]u8 = null;
        var topic_len: c.int = 0;

        const receive_rc = c.MQTTClient_receive(mqtt_client, &topic_name, &topic_len, &msg, 1000);
        if (receive_rc == c.MQTTCLIENT_SUCCESS and msg != null) {
            const topic = topic_name[0..topic_len];

            if (std.mem.eql(u8, topic, Topics.valve_command)) {
                try handleValveCommand(&app_state, msg);
            } else {
                log.warn("Received message on unknown topic: {s}", .{topic});
            }

            c.MQTTClient_freeMessage(&msg);
            c.MQTTClient_free(topic_name);
        } else if (receive_rc != c.MQTTCLIENT_SUCCESS and receive_rc != c.MQTTCLIENT_TIMEOUT) {
            log.err("MQTTClient_receive failed, return code {d}", .{receive_rc});
            break;
        }

        // Sleep briefly if no message received
        if (receive_rc == c.MQTTCLIENT_TIMEOUT) {
            std.time.sleep(10 * std.time.millisecond);
        }
    }
}

// Handle Valve Command Messages
fn handleValveCommand(app_state: *AppState, message: *c.MQTTClient_message) !void {
    // Ensure message.payload is not null
    if (message.payload == null) return;

    // Parse JSON payload
    const payload = @as([*]const u8, message.payload)[0..message.payloadlen];
    const valve_cmd = try parseValveCommand(app_state.allocator, payload);

    // Actuate Valve
    try app_state.valve_controller.actuate(valve_cmd.name, valve_cmd.state);
}

// Parse Valve Command from JSON
fn parseValveCommand(allocator: *std.mem.Allocator, payload: []const u8) !struct { name: []const u8, state: []const u8 } {
    var parser = std.json.Parser.init(allocator, 32);
    defer parser.deinit();

    const json_value = try parser.parse(payload);
    const root = json_value.asObject();

    const name_node = try root.get("valve_name");
    const state_node = try root.get("state");

    const name = try name_node.getString();
    const state = try state_node.getString();

    return .{ .name = name, .state = state };
}

// Publish Pressure Data
fn publishPressureData(app_state: *AppState) !void {
    while (true) {
        // Read Pressure Data
        const pressure = try app_state.pressure_sensor.read();

        // Create JSON Payload
        const json_payload = try std.fmt.allocPrint(app_state.allocator, "{{\"pressure\": {f}}}", .{pressure});
        defer app_state.allocator.free(json_payload);

        // Publish to MQTT Broker
        var pubmsg = c.MQTTClient_message{
            .payload = json_payload.ptr,
            .payloadlen = c.int(json_payload.len),
            .qos = 0,
            .retained = 0,
            .dup = 0,
            .struct_id = "MQTM",
            .struct_version = 0,
        };

        c.MQTTClient_publishMessage(app_state.mqtt_client, Topics.pressure_data, &pubmsg, null);

        // Sleep for specified interval
        std.time.sleep(std.time.millisecond * 100); // 100ms interval
    }
}

// Publish Temperature Data
fn publishTemperatureData(app_state: *AppState) !void {
    while (true) {
        // Read Temperature Data
        const temperature = try app_state.thermocouple_sensor.read();

        // Create JSON Payload
        const json_payload = try std.fmt.allocPrint(app_state.allocator, "{{\"temperature\": {f}}}", .{temperature});
        defer app_state.allocator.free(json_payload);

        // Publish to MQTT Broker
        var pubmsg = c.MQTTClient_message{
            .payload = json_payload.ptr,
            .payloadlen = c.int(json_payload.len),
            .qos = 0,
            .retained = 0,
            .dup = 0,
            .struct_id = "MQTM",
            .struct_version = 0,
        };

        c.MQTTClient_publishMessage(app_state.mqtt_client, Topics.temperature_data, &pubmsg, null);

        // Sleep for specified interval
        std.time.sleep(std.time.millisecond * 100); // 100ms interval
    }
}

// Publish Load Cell Data
fn publishLoadCellData(app_state: *AppState) !void {
    while (true) {
        // Read Load Cell Data
        const load_cell_value = try app_state.load_cell_sensor.read();

        // Create JSON Payload
        const json_payload = try std.fmt.allocPrint(app_state.allocator, "{{\"load_cell\": {f}}}", .{load_cell_value});
        defer app_state.allocator.free(json_payload);

        // Publish to MQTT Broker
        var pubmsg = c.MQTTClient_message{
            .payload = json_payload.ptr,
            .payloadlen = c.int(json_payload.len),
            .qos = 0,
            .retained = 0,
            .dup = 0,
            .struct_id = "MQTM",
            .struct_version = 0,
        };

        c.MQTTClient_publishMessage(app_state.mqtt_client, Topics.load_cell_data, &pubmsg, null);

        // Sleep for specified interval
        std.time.sleep(std.time.millisecond * 100); // 100ms interval
    }
}
