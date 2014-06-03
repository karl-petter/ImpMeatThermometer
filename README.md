ImpMeatThermometer
==================

ImpMeatThermometer is a modified version of the software for the [TurkeyProbe](https://github.com/electricimp/examples/tree/master/turkeyprobe).

It uses the exact same hardware and you will find the instructions how to build it in the [Imp Chef: Internet Connected BBQ Thermometer](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/) instructable. Though I did not have the exactly same probe but rather a Maverick ET-73 replacement probe. So there fore I needed to make some calibration to get mine to work. The calibration process works for any kind of termistor based meat probe.

Differences
===========

The differences to the original project is that the new version:
* uses Steinhart-Hart equation for resistance -> temperature conversion. This makes it rather easy to calculate the coefficients if a another probe is used by using the [Thermistor project code](http://thermistor.sourceforge.net/). Read more about the [probe calibration process](#anchors-probe-calibration-process).
* has [alarm temperature support](#anchors-alarm-support). The user can set an alarm temperature in the web GUI and the agent will call the ALARM_WEBHOOK_URL with a POST request the actual temperature as data in JSON
* has faster response in the web GUI, temperature is updated once every fifth second and the graph every 15th second
* has higher resolution in the graph. The Imp samples the probe once per second instead of once per minute.
* has more efficient communication with Xively. Readings are packed together and sent 10 at a time to not overload Xively.

Getting started
===============

1. Build the hardware by following the instructions on [Instructables](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/). [Step 1](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/) and [step 2](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step2/Wire-it-Up/).
2. Once you reach [step 3](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step3/Program-Your-Thermometer/), use the source code here instead of the one linked to.
3. Follow [step 4](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step4/Configure-a-Xively-Feed/) and configure Xively. And do not forget to put in the feed ID and the API key on [line 63](ImpMeatThermometer.agent.nut#L63) and [line 64](ImpMeatThermometer.agent.nut#L64) in the code.
4. Replace the ALARM_WEBHOOK_URL on [line 57](ImpMeatThermometer.agent.nut#L57) in the Agent code with a URL you want to be called once the alarm should go off. See the [alarm support](#anchors-alarm-support) section how I used Zapier and Pushover to get a push notfication in my iPhone.

[Step 5](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step5/Using-Your-Thermometer/) in the instructable explains how to use the thermometer and [step 6](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step6/A-Closer-Look-at-How-it-Works-Device-Code/) and [step 7](http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/step7/A-Closer-Look-at-How-it-Works-Agent-Code/) describes how the code works, i.e. the code before I modified it :) 

Alarm support
=============

To be really useful in a practical situation and the reason why I wanted to build a WiFi connected meat thermometer is that I want to be able to leave the barbecue and still monitor the temperature but also to receive an alarm when the correct temperature is reached. So that is why I needed to speed up the sampling and as well implement a way to get some kind of notification on the phone. 

The agent code can all an arbitrary webhook URL once the temperature limit has been reached. The code that does that are on [line 532](ImpMeatThermometer.agent.nut#L532) and onwards in the agent code. The reason why I go via Zapier is that I initially had the level detection in Xively but could not easily have the web GUI change the level so instead created webhook support in the agent and just set it to call my Zapier webhook. But that could as well be a direct hook to Pushover. 

You need to change [line 536](ImpMeatThermometer.agent.nut#L536) to look something like `local request =http.post(ALARM_WEBHOOK_URL+"?token=API_TOKEN&user=USER_KEY&message='Meat is done!');` where ALARM_WEBHOOK_URL should be set to `https://api.pushover.net/1/messages.json` with the parameters to the following values:
```
    token (required) - your application's API token
    user (required) - the user/group key (not e-mail address) of your user (or you)
    message (required) - your message
```

Setup Pushover
--------------

Go to [Pushover](https://pushover.net/) and register a new account if you do not already have one. Login and add you device. Also copy you API key to be used in Zapier.

Setup Zapier
------------

1. Go to [Zapier](https://zapier.com) and register a new account if you do not already have one. 
2. Login and click Make a Zap!. 
3. Choose a webhook as trigger for your Zap and a catch hook. 
4. Select Pushover as the action. Now you need you Pushover API key to authenticate Zapier. Do that and then select Push Notification in as the specific action to perform. Click Continue.
5. Copy the webhook URL into you agent code, [line 57](ImpMeatThermometer.agent.nut#L57). Click Continue.
6. Select correct Pushover account and click Continue.
7. No filtering for the webhook so click Continue.
8. Enter the message you would like to see in the push notification. The agent sends a `temp` field with the temperature when it triggered if you want to include that in the message. Click Continue once you are done.
9. Test your Zap!

Probe calibration process
=========================

The reason why I had the Maverick probe is because it was one of the recommended probes for the [LinkMeter project](https://github.com/CapnBry/HeaterMeter/wiki/HeaterMeter-Probes) and I had it at home already since I had been considering building a WiFi connected meat probe for some time.

After a bit of googling I found [this page](http://synfin.net/sock_stream/technology/arduino/calibrating-thermistors-for-the-arduino) which explained how to calculate the coefficients for the Steinhart-Hart equation.

To do that you need to [sample the thermistor resistance](#anchors-sample-the-resistance) at different temperatures and then [calcultate the coefficients](#anchors-calculate-the-coefficients). Basically what you need to do is to create a text file with several temperature readings as well as resistance readings and then run the little program and it will spit out the coefficients for you.

Sample the resistance
---------------------

To get the different readings at different temperatures I used my rather recently bought Sansaire. It was very convenient to use in this calibration process. This would of course work with any kind of similar sous-vide cooker or any other means to very precisely control the temperature of water
1. Fill up a big pot of cold water.
2. Place sous-vide cooker in it, set the desired temperature as low as possible for the first reading.
3. Place the meat probe in the water.
4. Place second reference thermometer in the water if you have one.
5. Make sure the code is running on the Imp and the Agent, see the device log.
6. Wait for the temperature to settle in and record the temperature(using the sous-vide thermometer or your second reference thermometer if used) and the resistance. Enter it into the `simu.txt` file.
7. Increase the temperature setting on the sous-vide to the next step and repeat step 6 until you have reached as close to 100 degrees as you can.

You will now have a `simu.txt` file that looks something like this:
```
16	278868
20	237518
25	198556
30	165291
35	138414
40	116711
45	98483
50	83438
55	70823
60	60505
65	51850
70	44594
75	38780
80	33478
85	29235
90	25475
95	22317
100	19420
```

Calculate the coefficients
--------------------------

Compile the coeff.c file if it was not already compiled for your environment. On my Mac I did:
```
cc coeff.c -o coeff
```

Then just run `./coeff` and you will get similar output.
```
Thermistor library version 1.0
Copyright (C) 2007, 2013 - SoftQuadrat GmbH, Germany

function readtable
==================
t=   16.00	r=278868.00
t=   20.00	r=237518.00
t=   25.00	r=198556.00
t=   30.00	r=165291.00
t=   35.00	r=138414.00
t=   40.00	r=116711.00
t=   45.00	r=98483.00
t=   50.00	r=83438.00
t=   55.00	r=70823.00
t=   60.00	r=60505.00
t=   65.00	r=51850.00
t=   70.00	r=44594.00
t=   75.00	r=38780.00
t=   80.00	r=33478.00
t=   85.00	r=29235.00
t=   90.00	r=25475.00
t=   95.00	r=22317.00
t=  100.00	r=19420.00

x=   12.54	y=   0.0035
x=   12.38	y=   0.0034
x=   12.20	y=   0.0034
x=   12.02	y=   0.0033
x=   11.84	y=   0.0032
x=   11.67	y=   0.0032
x=   11.50	y=   0.0031
x=   11.33	y=   0.0031
x=   11.17	y=   0.0030
x=   11.01	y=   0.0030
x=   10.86	y=   0.0030
x=   10.71	y=   0.0029
x=   10.57	y=   0.0029
x=   10.42	y=   0.0028
x=   10.28	y=   0.0028
x=   10.15	y=   0.0028
x=   10.01	y=   0.0027
x=    9.87	y=   0.0027

function orthonormal
====================
Evaluating polynom number 0
Polynom 0: 0.235702 0.000000 0.000000 0.000000 
Evaluating polynom number 1
Polynom 1: -3.210365 0.288204 0.000000 0.000000 
Evaluating polynom number 2
Polynom 2: 49.733860 -8.933876 0.399055 0.000000 
Evaluating polynom number 3
Polynom 3: -789.903730 212.943673 -19.074298 0.567716 
Testing orthonormal base
1.000000000000000 
-0.000000000000005 1.000000000000000 
0.000000000000099 -0.000000000000000 1.000000000000009 
-0.000000000003939 -0.000000000000107 -0.000000000000198 0.999999999999962 

function approx
===============
Approximating with polynom number 0
Approximating with polynom number 1
Approximating with polynom number 2
Approximating with polynom number 3
Steinhart-Hart coefficients
a[0] = -3.189496836200438e-05
a[1] = 3.107510196505785e-04
a[2] = -7.726827275253911e-06
a[3] = 4.106551835135709e-07

function testresult
===================
  15.935	278868.0	    16.0
  20.146	237518.0	    20.0
  24.954	198556.0	    25.0
  29.995	165291.0	    30.0
  34.996	138414.0	    35.0
  39.921	116711.0	    40.0
  44.944	 98483.0	    45.0
  49.968	 83438.0	    50.0
  55.059	 70823.0	    55.0
  60.068	 60505.0	    60.0
  65.097	 51850.0	    65.0
  70.127	 44594.0	    70.0
  74.896	 38780.0	    75.0
  80.033	 33478.0	    80.0
  84.879	 29235.0	    85.0
  89.915	 25475.0	    90.0
  94.869	 22317.0	    95.0
 100.197	 19420.0	   100.0

Maximal error=0.19742 at temperature=100.0
```

