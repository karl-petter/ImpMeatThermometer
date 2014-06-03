ImpMeatThermometer
==================

ImpMeatThermometer is a modified version of the software for the [TurkeyProbe](https://github.com/electricimp/examples/tree/master/turkeyprobe).

It uses the exact same hardware and you will find the instructions how to build it in the [Imp Chef: Internet Connected BBQ Thermometer]( http://www.instructables.com/id/Imp-Chef-Internet-Connected-BBQ-Thermometer/) instructable. Though I did not have the exactly same probe but rather a Maverick ET-73 replacement probe. So there fore I needed to make some calibration to get mine to work. The calibration process works for any kind of termistor based meat probe.

Differences
===========

The differences to the original project is that the new version:
* uses Steinhart-Hart equation for resistance -> temperature conversion. This makes it rather easy to calculate the coefficients if a another probe is used by using the [Thermistor project code](http://thermistor.sourceforge.net/). Read more about the [probe calibration process](#anchors-probe-calibration-process).
* has [alarm temperature support](#anchors-alarm-support). The user can set an alarm temperature in the web GUI and the agent will call the ALARM_WEBHOOK_URL with a POST request the actual temperature as data in JSON
* has faster response in the web GUI, temperature is updated once every fifth second and the graph every 15th second
* has higher resolution in the graph. The Imp samples the probe once per second instead of once per minute.
* has more efficient communication with Xively. Readings are packed together and sent 10 at a time to not overload Xively.

Probe calibration process
=========================

The reason why I had the Maverick probe is because it was one of the recommended probes for the [LinkMeter project](https://github.com/CapnBry/HeaterMeter/wiki/HeaterMeter-Probes) and I had it at home already since I had been considering building a WiFi connected meat probe for some time. 

Alarm support
=============

