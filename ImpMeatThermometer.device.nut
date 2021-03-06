/*
Copyright (C) 2014 electric imp, inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
and associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, 
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial 
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE 
AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/* Turkey Probe Device Firmware
 * Tom Byrne
 * 12/7/13
 *
 * Imp Meat Thermometer version
 * Karl-Petter Åkesson - yelloworb.com
 * Modified version with some improvements, see agent for details.
 * June 3rd 2014
 */
 
/* CONSTS and GLOBAL VARS ====================================================*/
const LONGPRESS_TIME    = 3; // button press time to wake the imp (seconds)
const INTERVAL          = 1; // log temp data every n seconds
const AVERAGE_SIZE      = 10;
const MAXSLEEP          = 86396; // max amount of time to sleep (1 day)
const R2                = 47000; // the resistance of the resistor in the voltage divider
const b_therm = 3977.0;
const t0_therm = 298.15;

i <- 0; // index of the averagebuffer rawval
rawval <- []; // buffer to save raw values and used to calculate an average over time

/* GLOBAL CLASS AND FUNCTION DEFINITIONS =====================================*/

// Reads the ADC input and calculates the Thermistor resistance based on current
// reading and 3.3V level. Uses the R2 resistor value
function getTermistorResistance() {
    local V3v3 = hardware.voltage();
    local Vmeasured = V3v3 * vtherm.read() / 65535.0; // vtherm.read() -> 0 - 65535
    local R_Therm = (R2*V3v3 / Vmeasured) - R2;
    return R_Therm;
}


//Calculate the ADC reading into temperature in Kelvin. (official Steinhart-Hart equations)
//This is split up (Selection) to allow for comparisons and easy selection of the
//Steinhart-Hart complexity levels.
//Steinhart-Hart Thermistor Equations (in Kelvin) Selections:
//1: Simplified: Temp = 1 / ( A + B(ln(R)) )
//2: Standard:   Temp = 1 / ( A + B(ln(R)) + D(ln(R)^3) )
//3: Extended:   Temp = 1 / ( A + B(ln(R)) + C(ln(R)^2) + D(ln(R)^3) )
//Obviously lower numbers are less accurate but are much faster.
function calculateTemperature(selection, resistance) {
    local a = [null,null,null,null];
    a[0] = -3.189496836200438e-05
    a[1] = 3.107510196505785e-04
    a[2] = -7.726827275253911e-06
    a[3] = 4.106551835135709e-07
    local lnResist = math.log(resistance); // no reason to calculate this multiple times.
    //build up the Steinhart-Hart equation depending on Selection.
    //Level 1 is used by all.
    local temperature = a[0] + (a[1] * lnResist);
    //If 2, add in level 2.
    if(selection>=2) { temperature = temperature + (a[3] * lnResist * lnResist * lnResist); }
    //If 3, add in level 3.
    if(selection>=3) { temperature = temperature + (a[2] * lnResist * lnResist); }
    //Final part is to invert
    temperature = (1.0 / temperature);
    return temperature;
}

function getTemp() {
    imp.wakeup(INTERVAL, getTemp);

    vtherm_en_l.write(0); // GND the lower end of the voltage divider
    imp.sleep(0.02); // sleep 0.02 s, ie 20 ms to allow resistor to stabalize before sample
    
    rawval[i] = getTermistorResistance(); // get a reading and add to the rawcal array that is used for calculating average over 10 samples
    vtherm_en_l.write(1); // put the end of the voltage divider high, no current drawn
    
    // calculate average over tha last ten samples
    local average = 0.0;
    foreach(idx,val in rawval) {
        average += val;
    }
    average = average/AVERAGE_SIZE;
    i++;
    if(i>=AVERAGE_SIZE) {
        i = 0;
    }

    server.log("Thermistor resistance average: " + average);

    local temp_K = calculateTemperature(3, average);
    local temp_C = temp_K - 273.15;
    
    agent.send("temp",{"temp":temp_C,"vbat":hardware.voltage()});
}

function goToSleep() {
    server.log("Going into sleep ...");
    wake.configure(DIGITAL_IN_WAKEUP); // set the imp to wake on input on pin 1
    // go to sleepfor max sleep time (1 day minus 5 seconds)
    server.sleepfor(MAXSLEEP);
}

function btnPressed() {
    // wait to see if this is a long press, and go to sleep if it is
    local start = hardware.millis();
    while ((hardware.millis() - start) < LONGPRESS_TIME*1000) {
        if (!hardware.pin1.read()) {return;}
    }
    goToSleep();
}

/* AGENT EVENT HANDLERS ======================================================*/
agent.on("sleep", function(val) {
    imp.onidle(function() {
        goToSleep();
    }); 
});
 
agent.on("needDeviceId", function(val) {
    agent.send("deviceId",hardware.getdeviceid());
}); 
 
/* RUNTIME BEGINS HERE =======================================================*/

// configure hardware
wake            <- hardware.pin1;

vtherm_en_l     <- hardware.pin8;
vtherm_en_l.configure(DIGITAL_OUT);

vtherm          <- hardware.pin9;
vtherm.configure(ANALOG_IN);

// check wakereason and make this a shallow wake if necessary
if ((hardware.wakereason() == WAKEREASON_PIN1) || (hardware.wakereason() == WAKEREASON_TIMER)) {
    local start = hardware.millis();
    while ((hardware.millis() - start) < LONGPRESS_TIME*1000) {
        if (!hardware.pin1.read()) {
            goToSleep();
        }
    }
    
    // if we made it here, somebody's just long-pressed the power button to wake the imp
    // go ahead and boot right up.
}

// not a shallow wake; fire up the radio and let's cook a turkey
imp.setpowersave(true); // save juice, as this application is not latency-critical

wake.configure(DIGITAL_IN, btnPressed);

vtherm_en_l.write(0);
imp.sleep(0.02); // sleep 0.02 s, ie 20 ms to allow resistor to stabalize before sample
// fill the rawval average buffer with a first reading
rawval = array(AVERAGE_SIZE, getTermistorResistance());
vtherm_en_l.write(1);

agent.send("justwokeup",hardware.getdeviceid());
getTemp();