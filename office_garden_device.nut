// Copyright (c) 2014 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT
// 
// Imp Balcony Garden Monitor

// GLOBALS AND CONSTS ----------------------------------------------------------
const SLEEPTIME = 900; // 15 minutes in seconds

// FUNCTION AND CLASS DEFS -----------------------------------------------------
class SHT10 {
    // cmds
    static SHT10_ADDR           = 0x0;  //0b000, 3 bits
    static SHT10_CMD_TEMP       = 0x03; //0b00011, 5 bits
    static SHT10_CMD_RH         = 0x05; //0b00101, 5 bits
    static SHT10_CMD_RDSTATUS   = 0x07; //0b00111
    static SHT10_CMD_WRSTATUS   = 0x06; //0b00110
    static SHT10_CMD_SOFTRESET  = 0x1E; //0b1110
    
    static TIMEOUT          = 0.5; // seconds
    static TIMEOUT_ACK      = 5; //ms
    static SOFTRESET_TIME   = 0.011; // seconds
    
    static D1            = -39.7;
    static D2_14         =  0.01; // coeff for 14-bit res (temp)
    static D2_12         =  0.04; // coeff for 12-bit res (temp)
    static C1            = -2.0468;
    static C2_12         =  0.0367; // coeff for 12-bit res (rh)
    static C2_8          =  0.5872; // coeff for 8-bit res (rh)
    static C3_12         = -0.0000015955; // 12-bit res (rh)
    static C3_8          = -0.00040845; // 8-bit res (rh)
    static T1            =  0.01;
    static T2_12         =  0.00008; // coeff for 12-bit res (rh)
    static T2_8          =  0.00128; // coeff for 8-bit res (rh)
    static AMBIENT       =  25.0;
    
    dta = null;
    clk = null;
    rhRes = null;
    tempRes = null;
    
    // class constructor
    // Input: 
    //      _clk: hardware pin for the clock line
    //      _dta: hardware pin for the data line
    // Return: (None)
    constructor(_clk, _dta) {
        clk = _clk;
        dta = _dta;
        
        init();
    }
    
    function init() {
        softReset();
        local status = getStatus();
        if ("err" in status) throw err;
        rhRes = status.rhRes;
        tempRes = status.tempRes;
    }
    
    // Clock Pulse
    // Input: number of pulses, defaults to 1 (int)
    // Return: (none)
    function _pulseClk(numPulses = 1) {
        for (local i = 0; i < numPulses; i++) {
            clk.write(1);
            clk.write(0);
        }
    }
    
    // Send and arbitrary Byte
    function _sendByte(byte) {
        byte = byte & 0xFF;
        clk.write(0);
        for (local i = 7; i >= 0; i--) {
            dta.write((byte & (0x01 << i)) ? 1 : 0);
            _pulseClk();
        }
    }
    
    // Send a Command Byte (5 command bits and 3 address bits)
    // Includes transaction start sequence
    function _sendCmd(cmd) {
        _sendStart();
        cmd = ((SHT10_ADDR & 0x3) << 5) | (cmd & 0x1F);
        _sendByte(cmd);
    }
    
    // Send Transmission Start Cmd
    function _sendStart() {
        clk.write(0);
        dta.write(1);
        clk.write(1);
        dta.write(0);
        clk.write(0);
        clk.write(1);
        dta.write(1);
        clk.write(0);
    }
    
    // get an ACK from the sensor after sending a command
    // Input: None
    // Return: True on ACK recieved, false on ACK timeout
    function _gotAck() {
        dta.configure(DIGITAL_IN_PULLUP);
        local start = hardware.millis();
        while (dta.read() && (hardware.millis() - start > TIMEOUT_ACK));
        dta.configure(DIGITAL_OUT);
        dta.write(0);
        // clock past the ACK (or the timeout, whatever)
        _pulseClk();
        if (hardware.millis() - start > TIMEOUT_ACK) return false;
        return true;
    }
    
    // Read an 8-bit word from the sensor
    // Input: None
    // Return: integer
    // Used to read the status register
    function _read8() {
        local result = 0;
        local checksum = 0;
        dta.configure(DIGITAL_IN_PULLUP);
        // msb first
        for (local i = 1; i <= 8; i++) {
            result += (dta.read() << (8 - i));
            _pulseClk();
        }
        // ACK and read the checksum
        // TODO: handle the checksum!
        dta.configure(DIGITAL_OUT);
        dta.write(0);
        _pulseClk();
        dta.configure(DIGITAL_IN_PULLUP);
        for (local i = 1; i <= 8; i++) {
            checksum += (dta.read() << (8 - i));
            _pulseClk();
        }
        // ACK the checksum
        dta.configure(DIGITAL_OUT);
        dta.write(0);
        _pulseClk();
        return result;
    }
    
    // Read a 16-bit word from the sensor
    // Input: None
    // Return: integer
    // used to retrieve sensor readings (temp, rh)
    function _read16() {
        dta.configure(DIGITAL_IN_PULLUP);
        local result = 0;
        // read high byte, msb first
        for (local i = 1; i <= 8; i++) {
            result += (dta.read() << (16 - i));
            _pulseClk();
        }
        // clock out one low bit to ack
        dta.configure(DIGITAL_OUT);
        dta.write(0);
        _pulseClk();
        dta.configure(DIGITAL_IN_PULLUP);
        // read low byte, msb first
        for (local i = 1; i <= 8; i++) {
            result += (dta.read() << (8 - i));
            _pulseClk();
        }
        // Hold DATA pin high to ignore the checksum and put device back to sleep
        // TODO: handle the checksum!
        dta.configure(DIGITAL_OUT);
        dta.write(1);
        _pulseClk();
        return result;
    }
    
    // set a specific bit in the status register
    // Input: bit to set (0-based), state (1 or 0)
    // Return: None
    function _setStatusBit(bit, state) {
        _sendCmd(SHT10_CMD_RDSTATUS);
        if (!_gotAck()) throw "timed out waiting for ACK on CMD_RDSTATUS";
        local byte = _read8();
        //server.log(format("STATUS Reg: 0x%02X",byte));
        if (state) {
            byte = byte | (0x01 << bit);
        } else {
            byte = (byte & ~(0x01 << bit) & 0x07);
        }
        //server.log(format("Writing back 0x%02X",byte));
        _sendCmd(SHT10_CMD_WRSTATUS);
        if (!_gotAck()) throw "timed out waiting for ACK on CMD_WRSTATUS";
        _sendByte(byte);
        if (!_gotAck()) throw "timed out waiting for ACK new Status Register Byte";
    }
    
    // issue a soft reset
    // clears the status register
    // wait 11ms before sending other commands
    function softReset() {
        _sendCmd(SHT10_CMD_SOFTRESET);
        imp.sleep(SOFTRESET_TIME);
    }
    
    // read the Status Register
    // returns a table with the following keys:
    // "lowVoltDet": (bool) low voltage (< 2.47V) detected (default false)
    // "heater": (bool) heater on (default false)
    // "noReloadFromOTP": (bool) true if not reloading from OTP (default false)
    // "rhRes": (integer) bit resolution of RH measurement (12 bit default, can be set to 8)
    // "tempRes": (integer) bit resolution of temp measurement(14 bit default, can be set to 12)
    // 
    // If an error occurs during reading, the table returned will contain only the "err" key with the error
    function getStatus() {
        _sendCmd(SHT10_CMD_RDSTATUS);
        if (!_gotAck()) return {"err": "timed out waiting for ACK on CMD_RDSTATUS"};
        local byte = _read8();
        //server.log(format("0x%02X", byte));
        local result = {"lowVoltDet": false, "heater": false, "noReloadFromOTP": false, "rhRes": 12, "tempRes": 14};
        if (byte & 0x40) result.lowVoltDet = true; 
        if (byte & 0x04) result.heater = true;
        if (byte & 0x02) result.noReloadFromOTP = true;
        if (byte & 0x01) {
            result.rhRes = 8;
            result.tempRes = 12;
        }
        return result;
    }

    function setLowRes() {
        _setStatusBit(0, 1);
        local status = getStatus();
        if ("err" in status) throw err;
        rhRes = status.rhRes;
        tempRes = status.tempRes;
    }
    
    function setHighRes() {
        _setStatusBit(0, 0);
        local status = getStatus();
        if ("err" in status) throw err;
        rhRes = status.rhRes;
        tempRes = status.tempRes;
    }
    
    function setHeater(state) {
        _setStatusBit(2, state);
    }
    
    function setOtpReload(state) {
        if (state) _setStatusBit(1, 0);
        else _setStatusBit(1, 1);
    }
    
    // read the temperature
    // Input: callback function, takes 1 argument (table)
    // Return: None
    // Callback will be called with table containing at least the "temp" key
    // If an error occurs, the "err" key will be present in the table
    function getTemp(cb) {
        _sendCmd(SHT10_CMD_TEMP);
        if (!_gotAck()) return {"err": "timed out waiting for ACK on CMD_TEMP"};
        // schedule a callback to catch a timeout
        local response_timer = imp.wakeup(TIMEOUT, function() {
            // cancel state change callback
            dta.configure(DIGITAL_OUT);
            cb({"err": "temperature reading timed out", "temp": 0});
        }.bindenv(this));
    
        // wait for SHT10 to pull DATA line low
        dta.configure(DIGITAL_IN_PULLUP, function() {
            if (dta.read()) return;
            imp.cancelwakeup(response_timer);
            // choose the correct D2 constant for our current resolution
            local D2 = D2_14;
            if (tempRes == 12) D2 = D2_12 
            // calculate and return
            cb({"temp": D1 + (D2 * _read16())});
        }.bindenv(this));
    }
    
    // read the temperature and relative humidity
    // Input: callback function, temperature for compensation (optional)
    // Return: None
    // Callback will be called with one argument (table)
    // Table will contain at least the "rh" key, with relative humidity as a percentage (float)
    // If an error occurs, table will contain "err" key
    function getTempRh(cb, temp = null) {
        // user skipped putting in the temp, so we'll go get it
        if (temp == null) {
            // go read the temp
            getTemp(function(tempResult) {
                if ("err" in tempResult) {
                    // if the temp result failed, call the getTempRh callback with an error
                    cb({"err": tempResult.err, "temp": tempResult.temp, "rh": 0.0}); 
                    return;
                }
                // if getTemp manages to get the temp, it calls us back with it 
                getTempRh(cb, tempResult.temp);
                // we've gotten through getTemp and back to getTempRh with the temp now, so end this path
                return;
            });
            // we've scheduled getTemp, which will call us back when done, so end this path
            return;
        }
        
        // we'll wind up here if getTemp calls us back or if the user calls with temp explicitly
        _sendCmd(SHT10_CMD_RH);        
        if (!_gotAck()) return {"err": "timed out waiting for ACK on CMD_RH"};
        local response_timer = imp.wakeup(TIMEOUT, function() {
            // cancel state change callback
            dta.configure(DIGITAL_OUT);
            cb({"err": "humidity reading timed out", "temp": temp, "rh": 0});
        }.bindenv(this));
        dta.configure(DIGITAL_IN_PULLUP, function() {
            if (dta.read()) return;
            imp.cancelwakeup(response_timer);
            local result = _read16();
            // choose correct coefficients for our current resolution
            local C2 = C2_12;
            local C3 = C3_12;
            local T2 = T2_12;
            if (rhRes == 8) {
                C2 = C2_8;
                C3 = C3_8;
                T2 = T2_8;
            }
            local unComp = C1 + (C2 * result) + (C3 * result * result);
            local rhComp = (temp - AMBIENT) * (T1 + (T2 * result)) + unComp;
            cb({"temp": temp, "rh": rhComp});
        }.bindenv(this));
    }
}

function readBatt() {
    local vbat = 0;
    local vcc = 0;
    for (local i = 0; i<10; i++) {
        vbat += batt.read();
        vcc += hardware.voltage();
    }
    vcc = vcc / 10.0;
    vbat = ((vbat / 10.0) / 65535.0 ) * vcc * 10.1 ;
    return vbat;
}

// RUNTIME START ---------------------------------------------------------------

imp.setpowersave(true);

clk1 <- hardware.pin6;
dta1 <- hardware.pin9;
clk2 <- hardware.pin8;
dta2 <- hardware.pin7;
batt <- hardware.pinB;
batt.configure(ANALOG_IN);

sensor1 <- SHT10(clk1, dta1);
sensor2 <- SHT10(clk2, dta2);

data <- {};
data.battery <- readBatt();
server.log(format("Battery: %0.1f", data.battery) + " volts");

sensor1.getTempRh(function(result1) {
    if ("err" in result1) {
        server.error(result1.err);
    } else {
        server.log(format("Sensor 1 Temperature: %0.1f C & Humidity: %0.1f", result1.temp, result1.rh) + "%");
        data.soil_temp_1 <- result1.temp;
        data.soil_humid_1 <- result1.rh;
        sensor2.getTempRh(function(result2) {
            if ("err" in result) {
                server.error(result2.err);
            } else {
                server.log(format("Sensor 2 Temperature: %0.1f C & Humidity: %0.1f", result2.temp, result2.rh) + "%");
                data.soil_temp_2 <- result2.temp;
                data.soil_humid_2 <- result2.rh;
                agent.send("data", data);
            }
        });
    }
});

// give us 10s to get a blinkup started if we need before going off to sleep
imp.wakeup(10, function() {
    imp.onidle(function() {
        if ( readBatt() < 13 ) {
            server.sleepfor(SLEEPTIME);
        }
    });
});