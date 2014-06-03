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

/* Turkey Probe Agent Firmware
 * Tom Byrne
 * 12/18/13
 *
 * Imp Meat Thermometer version
 * Karl-Petter Åkesson - yelloworb.com
 * Modified version with some improvements
 * - uses Steinhart-Hart equation for resistance -> temperature conversion
 *   This makes it rather easy to calculate the coefficients if a another
 *   probe is used by using the Thermistor project code - http://thermistor.sourceforge.net/
 * - alarm temperature support. The user can set an alarm temperature in the 
 *   web GUI and the agent will call the ALARM_WEBHOOK_URL with a POST request
 *   the actual temperature as data in JSON
 * - Much faster response in the web GUI, temperature is updated once per second
 *   and the graph every 10th second
 * - readings are packed together and sent 10 at a time to not overload Xively
 * June 3rd 2014
 *
 * TODOs
 * - none
 */ 
 
/* CONSTS AND GLOBALS ========================================================*/ 
// Sleep timers. Values in seconds. These use a simple heuristic to determine if we should
// time out due to inactivity and send the device to sleep.
const START_SLEEP_TIMER = 120; // amount of time sleep timer starts with
const MAX_SLEEP_TIMER = 1800; // maximum value we let the don't-sleep-due-to-activity-timer grow to
const MIN_CHANGE = 1; // minimum amount of temp change in measurement interval to add time to the sleepTimer
const TIMER_DEC_INTERVAL = 10; // call the checkSleepTimer() every 10th second
lastTemp <- 0;
sleepTimer <- (START_SLEEP_TIMER+10); // countdown timer; sleep if no activity during this time in seconds. Constantly refilled while active.
const MAX_AUTOSLEEP_TEMP = 30; // max temp that under which autosleep is active, wont sleep if above this

const THRESHOLD_HYSTERESIS  = 5.0; // degrees below threshold at which the alarm is resetted.
const READINGS_BUFFER_SIZE  = 10; // number of temperature readings to buffer up before sending to Xively
temperatureReadings <- [];

const ALARM_WEBHOOK_URL = "YOUR_WEBHOOK_URL";
alarmThreshold <- 55;
aboveThreshold <- false;
dateLastReading <- 0;

// Xively credentials to post to feed and retrieve graphs on the UI
const XIVELY_API_KEY = "YOUR KEY HERE";
const XIVELY_FEED_ID = "YOUR FEED ID HERE";
Xively <- {};  // this makes a 'namespace'

// low battery warning threshold voltage
const LOW_BATT_THRESH = 2.8; // volts

// Device ID used to create new channels in this feed for each new turkey probe
config <- server.load();
if (!("myDeviceId" in config)) {
    // grab the pre-saved device ID from the server if it's there
    // if it isn't, we've never seen this device before (or the server forgot - unlikely!)
    // we will request a device ID from the device if we make it past class declarations without
    // the device doing an "I just woke up" check-in.
    config.myDeviceId <- null;
}

// Alarm for low battery
lowBattAlarm <- 1; // default to true; will be cleared on first temp post

// UI webpage will be stored at global scope as a multiline string
WEBPAGE <- @"<h2>Agent initializing, please refresh.</h2>";

/* GLOBAL FUNCTIONS AND CLASS DEFINITIONS ====================================*/

/* Pack up the UI webpage. The page needs the xively parameters as well as the device ID,
 * So we need to wait to get the device ID from the device before packing the webpage 
 * (this is done by concatenating some global vars with some multi-line verbatim strings).
 * Very helpful that this block can be compressed, as well. */
function prepWebpage() {
    WEBPAGE = @"
    <!DOCTYPE html>
    <html lang='en'>
      <head>
        <meta charset='utf-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <meta name='description' content=''>
        <meta name='author' content=''>
    
        <title>Electric Imp Connected Meat Thermometer</title>
        <link href='data:image/x-icon;base64,AAABAAEAEBAAAAAAAABoBQAAFgAAACgAAAAQAAAAIAAAAAEACAAAAAAAAAEAAAAAAAAAAAAAAAEAAAAAAAAAAAAABSV/AAgQmgAAA2IAWHzMACdRwgAEElAAVoHSACVawgBDcsEARHPEAPv+/wABG80A//7/AO7o6wAXLuoAAzWvADZltgBNfM0AEBluAB064QALB0IAIjmFAD1rvwApdOMAPmrFADdWnABDbr8AVYXWAAECGQD8+fEAV4XWAERvwgD+/PEARnDFAFRqswBIcsIABQYcADI+5AD9/f0ANnjmAAUaaQAJGssAJzhfABAevAAkQV8ALUqdAC5UlwAzIh4AKlamAAEWQwAqIzwAE0OkAEdpugD7+vUAQ3LDAERxyQAuYLsASHbGAC1K5QBTZ8YACDCiAAEc0gBKdcwAFjPpABNRxQAmFjoA7vH2ADZQlQBAa8EAMlOnAApCvQD09/8Ad5DUAERtvgAzWqEAtLzPAPj7+QBZhNUAAAl3ACEtWwBGdMEA//zzAAoaUAD/9/8A/fr/AEpuygApU90A///8AGKK1QAdIJcAOGe2AAMJQgAZduwAIEBwAAwNlQAsT7cAPE6ZAEVuuQATDZ4A8v/9AD1DVQBGccIAJkeOAP/7+gBJeb8AV11sACIZKgANStYAUXi8ABRMygBLessAMHDJAPHv+wA9bL0AAAjGAFSD1ABVg9QAIVrHACdDgwBEc8kA/f34AGGF0QD///4ADAqFAAoILwAFEywACyxbAD9jtQAPIWcAOEWbACBoqgASJHAAE5nrAEFwwQAoPocADCrkAEBYjABDccQAJ1bOAPj+/AAnfvQATW24ABIdOAAcTJ8A/v//AENdmwD///8AS3PKADlfswAYL5EAPUDmADNKkABBZ6cAFDKjALGxzQA+bL8AARVOAAkRSwAMGDwA+f7rAPv79AAKQsoA+fz3ACFkzAAeIRgARXTFACYpXAD//v0AEx2kABguPwAcVr4ARGyuAPH68gBIaqgA9PP4AAgTQABBacAAEitsACE3+gC6ucIARESjAAtFwgAXHuYARnDDAP/1/gAPIT0A/fv+AP7+/gD//v4AG2jiAA46hwAjOloAIZztABkwhAAIVtoADQ6CACE3fgAQV9QAAiV/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJOTvCcnJ0MrGi8tTFiTk5OTqA5QpLCQERecclufjKG9C2V+woBFMQqKijcJlVasHjaLoplKeDqmNzcKG2YiiXGtMscGlAd1ElFiN4EgJCNqYGvDPXpOH3Q/soaYII6rV24wbJpaWRxvGX8DLml2hLWbXiy3KqlJS0Z8YVOWvl0YeSaXQAI+c5I4Y4K/KTSlBFU7FcQPiE8BNV+Fwa7GxVJkoH0zswwQR7E8noOHjzlIk3shFBMdQbYWuGcFRFxNk5OTDa+0nbpCcCh3JQije5OTk5N7e2inqm2NwLlUu5GTAAAAAAAAAAAAAAAAAAAAAP//AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//AAA=' rel='icon' type='image/x-icon' />
        <!-- Bootstrap core CSS -->
        <link href='https://netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css' rel='stylesheet'>
      </head>
    
      <body>
    
        <nav id='top' class='navbar navbar-fixed-top navbar-inverse' role='navigation'>
          <div class='container'>
            <div class='navbar-header'>
              <button type='button' class='navbar-toggle' data-toggle='collapse' data-target='.navbar-ex1-collapse'>
                <span class='sr-only'>Toggle navigation</span>
                <span class='icon-bar'></span>
                <span class='icon-bar'></span>
                <span class='icon-bar'></span>
              </button>
              <a class='navbar-brand'>Electric Imp Meat Thermometer</a>
            </div>
    
            <!-- Collect the nav links, forms, and other content for toggling -->
            <div class='collapse navbar-collapse navbar-ex1-collapse'>
              <ul class='nav navbar-nav'>
              </ul>
            </div><!-- /.navbar-collapse -->
          </div><!-- /.container -->
        </nav>
        
        <div class='container'>
          <div class='row' style='margin-top: 80px'>
            <div class='col-md-offset-2 col-md-8 well'>
                <div class='row'>
                  <div class='col-md-12 form-group'>
                    <h2 style='display: inline'>Probe <span id='currentTemp'>offline</span></h2>
                    <button type='button' class='btn btn-default' style='vertical-align: top; margin-right: 10px; margin-left: 10px;' onclick='toggleUnits()'>&degC/&degF</button>
                    <h2 style='display: inline'>Alarm:</h2>
                    <form style='display: inline; position: absolute; margin-top: 7px; margin-left: 8px;'><input onchange='setAlarmThreshold()' value='" +alarmThreshold + @"' type='number' id='alarmThreshold' max='100' min='20'></form>
                  </div>
                </div>
                  <div id='lowbatt' class='alert alert-warning' style='display:none'>Warning: Low Battery</div>
                  <div id='graphcontainer'>
                    <img id='tempgraph' style='margin-left: 15px' src=''></img>
                  </div>
				  <div class='slider' style='width: 600px; height: 15px; margin: auto;'></div>
                  <div style='padding-top: 10px' class='col-md-12 form-group'>
                    <button type='button' class='btn btn-default' style='vertical-align: top; margin-left: 15px;' onclick='graph5min()'>5 min</button>
                    <button type='button' class='btn btn-default' style='vertical-align: top; margin-left: 15px;' onclick='graph30min()'>30 min</button>
                    <button type='button' class='btn btn-default' style='vertical-align: top; margin-left: 15px;' onclick='graph1hour()'>1 hour</button>
                    <button type='button' class='btn btn-default' style='vertical-align: top; margin-left: 15px;' onclick='graph3hour()'>3 hour</button>
                  </div>
                </div>
                <div class='row'>
                </div>
            </div>
          </div>
          <hr>
    
          <footer>
            <div class='row'>
              <div class='col-lg-12'>
                <p class='text-center'>Copyright &copy; Electric Imp 2013 &middot; <a href='http://facebook.com/electricimp'>Facebook</a> &middot; <a href='http://twitter.com/electricimp'>Twitter</a></p>
              </div>
            </div>
          </footer>
          
        </div><!-- /.container -->
    
      <!-- javascript -->
      <script src='http://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js'></script>
      <script src='http://ajax.googleapis.com/ajax/libs/jqueryui/1.10.3/jquery-ui.min.js'></script>
      <script src='https://netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js'></script>
      <script src='http://d23cj0cdvyoxg0.cloudfront.net/xivelyjs-1.0.4.min.js'></script>
      <script>
        var XIVELY_KEY = '" + XIVELY_API_KEY + @"';
        var XIVELY_FEED_ID = '" + XIVELY_FEED_ID + @"';
        var XIVELY_BASE_URL = 'https://api.xively.com/v2/feeds/';
        var DEVICE_ID ='" + config.myDeviceId + @"';
        var graphwidth = document.getElementById('graphcontainer').offsetWidth - 30;
        var graphheight = graphwidth / 2;
        var XIVELY_PARAMS = 'width='+graphwidth+'&height='+graphheight+'&colour=00b0ff&timezone=UTC&b=true&g=true';
        var XIVELY_GRAPH_URL = XIVELY_BASE_URL + XIVELY_FEED_ID + '/datastreams/temperature'+DEVICE_ID+'.png' + '?' + XIVELY_PARAMS;
        var UNITS = 'C';
        var graphDuration = '1hour';
        
        var alarmThreshold = " +alarmThreshold + @";
        
        xively.setKey( XIVELY_KEY );
        
        var temperatureAndTresholdRefreshTimer;
        var graphRefreshTimer;
        var inFastRefreshState = true; // dual state for refreshing the web GUI
        var slowRefreshRateInterval  = 15; // slow refresh rate in seconds
        var fastRefreshRateInterval  = 5;  // fast refreh rate in seconds
        var graphRefreshRateInterval = 15; // graph refresh interval in seconds
          
        function graph5min() {
            graphDuration = '5minute';
            document.getElementById('tempgraph').src=XIVELY_GRAPH_URL+'&duration=5minute';
        }
        
        function graph30min() {
            graphDuration = '30minute';
            document.getElementById('tempgraph').src=XIVELY_GRAPH_URL+'&duration=30minute';
        }
        
        function graph1hour() {
            graphDuration = '1hour';
            document.getElementById('tempgraph').src=XIVELY_GRAPH_URL+'&duration=1hour';
        }
        
        function graph3hour() {
            graphDuration = '3hour';
            document.getElementById('tempgraph').src=XIVELY_GRAPH_URL+'&duration=3hour';
        }
        
        function refreshTemp() {
            tempURL = '" + http.agenturl() + @"/api/temperature';
            $.getJSON(
                tempURL,
                function(data) {
                    if('current_value' in data) {
                        if(data.current_value=='offline') {
                            if(inFastRefreshState) {
                                clearInterval(temperatureAndTresholdRefreshTimer);
                                clearInterval(graphRefreshTimer);
                                temperatureAndTresholdRefreshTimer = setInterval(refreshTempAndAlarm, slowRefreshRateInterval * 1000)
                                graphRefreshTimer = setInterval(refreshGraph, slowRefreshRateInterval * 1000);
                            }
                            // if in slow state, just stay there, do not change anything
                            
                            // change the information to offline
                            $('#currentTemp').html(data.current_value);
                        } else {
                            // if in the slow state, enter the fast
                            if(!inFastRefreshState) {
                                clearInterval(temperatureAndTresholdRefreshTimer);
                                clearInterval(graphRefreshTimer);
                                temperatureAndTresholdRefreshTimer = setInterval(refreshTempAndAlarm, fastRefreshRateInterval * 1000)
                                graphRefreshTimer = setInterval(refreshGraph, graphRefreshRateInterval * 1000);
                                inFastRefreshState = true;
                            }
                            // and if we are in the fast, lets stay there
                            
                            if (UNITS == 'C') {
                                $('#currentTemp').html(data.current_value+'&deg'+UNITS);
                            } else {
                                var temp = Math.round(10 * (data.current_value * 1.8 + 32.0)) / 10;
                                $('#currentTemp').html(temp+'&deg'+UNITS);
                            }
                        }
                    } else {
                        console.log('Unknown data in temperature query' + data);
                    }
                }
            );
        }
        
        function checkBatt() {
            var feedID        = XIVELY_FEED_ID,            
                datastreamID  = 'lowbatt'+DEVICE_ID;
                
            xively.datastream.get (feedID, datastreamID, function ( datastream ) {
                if (datastream['current_value'] == 1) {
                    console.log('low batt alert set!');
                    document.getElementById('lowbatt').style.display = 'block';
                } else {
                    document.getElementById('lowbatt').style.display = 'none';    
                }
            });
        }
        
        function refreshGraph() {
            checkBatt();
            document.getElementById('tempgraph').src=XIVELY_GRAPH_URL+'&duration='+graphDuration;        
        }
        
        function refreshAlarmThreshold() {
            alarmURL = '" + http.agenturl() + @"/api/alarm';
            $.getJSON(
                alarmURL,
                function(data) {
                    if('threshold' in data) {
                        alarmThreshold = data.threshold;
                        document.getElementById('alarmThreshold').value = alarmThreshold;
                    } else {
                        console.log('Unknown data in alarm threshold query' + data);
                    }
                }
            );
        }
        
        function setAlarmThreshold() {
            alarmThreshold = document.getElementById('alarmThreshold').value;
            alarmURL = '" + http.agenturl() + @"/api/alarm';
            console.log('Set threshold: ' + alarmURL);
            $.ajax({
                type: 'PUT',
                url: alarmURL,
                data: { 'threshold': alarmThreshold}
            });
        }
        
        function refreshTempAndAlarm() {
            refreshAlarmThreshold();
            refreshTemp();
        }
        
        function toggleUnits() {
            if (UNITS == 'F') {
                UNITS = 'C';
            } else {
                UNITS = 'F';
            }
            refreshTemp();
        }
        
        $.ajaxSetup({
            contentType : 
            'application/json', processData : false
        });
        $.ajaxPrefilter(
            function(options, originalOptions, jqXHR){
                if(options.data){
                    options.data = JSON.stringify(options.data);
                }
            }
        );
        
        // setInterval takes an interval in ms; multiply by 1000.
        refreshTempAndAlarm();
        refreshGraph();
        temperatureAndTresholdRefreshTimer = setInterval(refreshTempAndAlarm, fastRefreshRateInterval * 1000)
        graphRefreshTimer = setInterval(refreshGraph, graphRefreshRateInterval * 1000);
        
        // refresh the entire page if the viewport is resized to make sure the chart is the right size
        window.onresize = function(event) {
            document.location.reload(true);
        }
    
      </script>
      </body>
    
    </html>"
}

// Xively "library". See https://github.com/electricimp/reference/tree/master/webservices/xively
class Xively.Client {
    ApiKey = null;
    triggers = [];

    constructor(apiKey) {
        this.ApiKey = apiKey;
    }
    
    /*****************************************
     * method: PUT
     * IN:
     *   feed: a XivelyFeed we are pushing to
     *   ApiKey: Your Xively API Key
     * OUT:
     *   HttpResponse object from Xively
     *   200 and no body is success
     *****************************************/
    function Put(feed){
        local url = "https://api.xively.com/v2/feeds/" + feed.FeedID + ".json";
        local headers = { "X-ApiKey" : ApiKey, "Content-Type":"application/json", "User-Agent" : "Xively-Imp-Lib/1.0" };
        local request = http.put(url, headers, feed.ToJson());

        return request.sendsync();
    }
    
    /*****************************************
     * method: GET
     * IN:
     *   feed: a XivelyFeed we fulling from
     *   ApiKey: Your Xively API Key
     * OUT:
     *   An updated XivelyFeed object on success
     *   null on failure
     *****************************************/
    function Get(feed){
        local url = "https://api.xively.com/v2/feeds/" + feed.FeedID + ".json";
        local headers = { "X-ApiKey" : ApiKey, "User-Agent" : "xively-Imp-Lib/1.0" };
        local request = http.get(url, headers);
        local response = request.sendsync();
        if(response.statuscode != 200) {
            server.log("error sending message: " + response.body);
            return null;
        }
    
        local channel = http.jsondecode(response.body);
        for (local i = 0; i < channel.datastreams.len(); i++)
        {
            for (local j = 0; j < feed.Channels.len(); j++)
            {
                if (channel.datastreams[i].id == feed.Channels[j].id)
                {
                    feed.Channels[j].current_value = channel.datastreams[i].current_value;
                    break;
                }
            }
        }
    
        return feed;
    }

}
    
class Xively.Feed{
    FeedID = null;
    Channels = null;
    
    constructor(feedID, channels)
    {
        this.FeedID = feedID;
        this.Channels = channels;
    }
    
    function GetFeedID() { return FeedID; }

    function ToJson()
    {
        local json = "{ \"datastreams\": [";
        for (local i = 0; i < this.Channels.len(); i++)
        {
            json += this.Channels[i].ToJson();
            if (i < this.Channels.len() - 1) json += ",";
        }
        json += "] }";
        return json;
    }
}

class Xively.Channel {
    id = null;
    current_value = null;
    
    constructor(_id)
    {
        this.id = _id;
    }
    
    function Set(value) { 
        this.current_value = value; 
    }
    
    function Get() { 
        return this.current_value; 
    }
    
    function ToJson() {
        local data = {};
        local lastReading;
        data.id <- this.id;
        if(typeof this.current_value == "array") {
            local arr = this.current_value;
            local tempArray = clone arr;
            lastReading = tempArray.pop();
            local last_value = lastReading.value;
            data.datapoints <- tempArray;
            this.current_value = last_value;
        }
        data.current_value <- this.current_value;
        local result = http.jsonencode(data);
        return result;
    }
}

function postToXively(data,channel) {
    xivelyChannel <- Xively.Channel(channel+config.myDeviceId);
    xivelyChannel.Set(data);
    xivelyFeed <- Xively.Feed(XIVELY_FEED_ID, [xivelyChannel]);
    xivelyClient.Put(xivelyFeed);
}

/* DEVICE EVENT CALLBACKS ====================================================*/ 

device.on("justwokeup", function(deviceId) {
    server.log("Received word that Device "+deviceId+" just booted.");
    if (config.myDeviceId == null) {
        config.myDeviceId = deviceId;
        server.save(config);
        prepWebpage();
    }
    sleepTimer = START_SLEEP_TIMER;
});

device.on("deviceId", function(deviceId) {
    server.log("Received Device ID: "+deviceId);
    config.myDeviceId = deviceId;
    server.save(config);
    prepWebpage();
});

device.on("temp", function(data) {
    local d = date(time(),"l");
    dateLastReading = time();
    // 2013-04-22T00:35:43Z
    local datestring = format("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.month+1, d.day, d.hour, d.min, d.sec);
    
    local deltaTemp = math.abs(data.temp - lastTemp);
    lastTemp = data.temp;
    // only add time to the timer if we have activity, i.e. temperature change
    if (deltaTemp > MIN_CHANGE) {
        // TODO: Explain why modify sleeptimer depending on temperature change
        // why not reset it to the start value each time temperature changes?
        if (deltaTemp > 30) {
            sleepTimer += 60;
        } else {
            sleepTimer += deltaTemp * 2;
        }
    }
    // don't let the sleep timer exceed the preset max.
    if (sleepTimer > MAX_SLEEP_TIMER) {
        sleepTimer = MAX_SLEEP_TIMER
    };
    
    if(temperatureReadings.len() >= READINGS_BUFFER_SIZE) {
        temperatureReadings.clear();
    }
    temperatureReadings.push({at = datestring, value = format("%.1f",data.temp)});
    local status = (data.temp>alarmThreshold)?"is above":"is below";
    status += " " + alarmThreshold + " C";
    server.log("Temp(" + temperatureReadings.len() + "): " + temperatureReadings[temperatureReadings.len()-1].value + " C " + status);
    
    if(temperatureReadings.len() == READINGS_BUFFER_SIZE) {
        // post the datapoint to the Xively feed
        postToXively(temperatureReadings, "temperature");
    }
    
    // check alarmThreshold
    if(data.temp > alarmThreshold && !aboveThreshold) {
        aboveThreshold = true;
        server.log("Temperature above Threshold! Alert!");
        local request =http.post(ALARM_WEBHOOK_URL, {}, http.jsonencode({temp = format("%.1f",data.temp)}));
        local response = request.sendsync();
    } 
    if(data.temp < (alarmThreshold - THRESHOLD_HYSTERESIS) && aboveThreshold) {
        server.log("Alarm reseted!");
        aboveThreshold = false;
    }
    
    // check for low-battery issues
    server.log("Battery: "+data.vbat+" V");
    if (!lowBattAlarm && (data.vbat < LOW_BATT_THRESH)) {
        // set the low batt alarm and post it to xively
        server.log("Low battery alert!");
        lowBattAlarm = 1;
        postToXively(lowBattAlarm, "lowbatt")
    } else if (lowBattAlarm && (data.vbat > LOW_BATT_THRESH)) {
        // clear the low batt alarm and post it to xively
        lowBattAlarm = 0;
        postToXively(lowBattAlarm, "lowbatt")
        server.log("Low battery alert cleared.");
    }
});

/* HTTP REQUEST HANDLER =======================================================*/ 

http.onrequest(function(request, res) {
    server.log("New request");
    // we need to set headers and respond to empty requests as they are usually preflight checks
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers","Origin, X-Requested-With, Content-Type, Accept");
    res.header("Access-Control-Allow-Methods", "POST, GET, OPTIONS");

    // implementation of our simple REST API to set alarm threshold and read temperature
    if (request.path.find("/api") != null) {
        // alarm API
        if (request.path.find("/alarm") != null) {
            // read the alarm threshold
            if(request.method == "GET") {
                local data = {};
                data.threshold <- alarmThreshold;
                res.send(200,http.jsonencode(data));
            // set the alarm threshold
            } else if(request.method == "PUT") {
                try {
                    // Check if the the threshold was passed
                    local data = http.jsondecode(request.body);
                    if ("threshold" in data) {
                        alarmThreshold = data.threshold.tofloat();
                        alarmThreshold = alarmThreshold<20.0?20:alarmThreshold;
                        alarmThreshold = alarmThreshold>100.0?100:alarmThreshold;
                        aboveThreshold = false;
                        server.log("New threshold set to " + alarmThreshold + "C");
                    }
                    // send a response back to whoever made the request
                    res.send(200, "OK");
                } catch (e) {
                    // send a response indicating invalid JSON
                    response.send(500, "Invalid JSON string");
                }
            }
            // temperature API
        } else if (request.path.find("/temperature") != null) {
            // read the current temperature value, return 'offline' if reading is
            // older than 5 seconds
            if(request.method == "GET") {
                local data = {};
                if((dateLastReading == 0) || (time()-dateLastReading > 5)) {
                    data.current_value <- "offline";
                } else {
                    data.current_value <- temperatureReadings[temperatureReadings.len()-1].value;
                }
                res.send(200,http.jsonencode(data));
            }
        }
    } else if (request.path == "/sleep" || request.path == "/sleep/") {
        device.send("sleep",0);
        res.send(200, "Going to Sleep");
    } else {
        server.log("Agent got unknown request");
        server.log("Query:" + request.query + " path:" + request.path);
        res.send(200, WEBPAGE);
    }
});

function checkSleepTimer() {
    // recursively call checkSleepTimer in TIMER_DEC_INTERVAL
    imp.wakeup(TIMER_DEC_INTERVAL, checkSleepTimer); 
    sleepTimer -= TIMER_DEC_INTERVAL;
    if (sleepTimer < 0) {
        sleepTimer = 0
    };
    
    server.log("Sleep timer = " + sleepTimer);
    // if timed out and device is connected, tell it to sleep
    if ((sleepTimer == 0) && device.isconnected()) {
        // only send sleep if lastTemp is below MAX_AUTOSLEEP_TEMP
        if (lastTemp < MAX_AUTOSLEEP_TEMP) {
            // TODO: if app is open, don't sleep
            device.send("sleep",0);
        }
    }
}
/* RUNTIME BEGINS HERE =======================================================*/

server.log("Imp Meat Thermometer Agent Started.");

// instantiate our Xively client
xivelyClient <- Xively.Client(XIVELY_API_KEY);

// in case we've just restarted the agent, but not the device, call the device for 
// the device ID in 1 second if it doesn't ping us with an "I just booted" message
imp.wakeup(1, function() {
    if (config.myDeviceId == null) { device.send("needDeviceId",0); } else { prepWebpage(); };
});

// start running the auto-sleep watchdog timer
checkSleepTimer();