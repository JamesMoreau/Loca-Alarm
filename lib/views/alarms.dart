import 'package:flutter/material.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/loca_alert_state.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:loca_alert/views/map.dart';

class AlarmsView extends StatelessWidget {
  const AlarmsView({super.key});

  void openAlarmEdit(BuildContext context, Alarm alarm) {
    debugPrintInfo('Editing alarm: ${alarm.name}, id: ${alarm.id}.');

    // Copy the alarm to the buffer alarm. We don't do this inside the edit widget because rebuilds will cause the buffer alarm to be reset.
    var state = June.getState(() => LocaAlertState());
    state.bufferAlarm = Alarm(name: alarm.name, position: alarm.position, radius: alarm.radius, color: alarm.color, active: alarm.active);
    state.nameInputController.text = alarm.name;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return EditAlarmDialog(alarmId: alarm.id);
      },
    ).whenComplete(resetEditAlarmState);
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlertState(),
      builder: (state) {
        if (state.alarms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No alarms.'),
                ElevatedButton(
                  child: const Text('Add Some Alarms'),
                  onPressed: () {
                    addAlarm(Alarm(name: 'Dublin', position: const LatLng(53.3498, -6.2603), radius: 2000, color: AvailableAlarmColors.green));
                    addAlarm(Alarm(name: 'Montreal', position: const LatLng(45.5017, -73.5673), radius: 2000, color: AvailableAlarmColors.blue));
                    addAlarm(Alarm(name: 'Osaka', position: const LatLng(34.6937, 135.5023), radius: 2000, color: AvailableAlarmColors.purple));
                    addAlarm(Alarm(name: 'Saint Petersburg', position: const LatLng(59.9310, 30.3609), radius: 2000, color: AvailableAlarmColors.redAccent));
                    addAlarm(Alarm(name: 'San Antonio', position: const LatLng(29.4241, -98.4936), radius: 2000, color: AvailableAlarmColors.orange));
                  },
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Scrollbar(
            child: ListView.builder(
              itemCount: state.alarms.length,
              itemBuilder: (context, index) {
                var alarm = state.alarms[index];
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(alarm.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    leading: Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
                    subtitle: Text(alarm.position.toSexagesimal(), style: TextStyle(fontSize: 9, color: Colors.grey[700])),
                    onLongPress: () => openAlarmEdit(context, alarm),
                    onTap: () => openAlarmEdit(context, alarm),
                    trailing: Switch(
                      value: alarm.active,
                      activeColor: alarm.color,
                      thumbIcon: thumbIcon,
                      onChanged: (value) {
                        var updatedAlarmData = Alarm(name: alarm.name, position: alarm.position, radius: alarm.radius, color: alarm.color, active: value);
                        updateAlarmById(alarm.id, updatedAlarmData);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class EditAlarmDialog extends StatelessWidget {
  final String alarmId;

  const EditAlarmDialog({required this.alarmId, super.key});

  void saveBufferToAlarm() {
    var state = June.getState(() => LocaAlertState());

    // Replace the actual alarm data with the buffer alarm.
    var alarm = getAlarmById(alarmId);
    if (alarm == null) {
      debugPrintError('Cannot save alarm since no alarm exists with id $alarmId');
      return;
    }

    var bufferAlarmReference = state.bufferAlarm;
    if (bufferAlarmReference == null) {
      debugPrintError('Cannot save buffer alarm since it is null.');
      return;
    }

    bufferAlarmReference.name = state.nameInputController.text.trim();
    updateAlarmById(alarmId, bufferAlarmReference);
  }

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlertState(),
      builder: (state) {
        var bufferAlarmReference = state.bufferAlarm;
        if (bufferAlarmReference == null) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    const Text(
                      'Edit Alarm',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      child: const Text('Save'),
                      onPressed: () {
                        saveBufferToAlarm();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: ListView(
                    children: [
                      Text('Name', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      TextFormField(
                        textAlign: TextAlign.center,
                        controller: state.nameInputController,
                        onChanged: (value) => state.setState(),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              state.nameInputController.clear();
                              state.setState();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Color', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircleAvatar(
                                backgroundColor: bufferAlarmReference.color,
                                radius: 20,
                                child: const Icon(Icons.pin_drop_rounded, color: Colors.white),
                              ),
                            ),
                            for (var color in AvailableAlarmColors.allColors.values) ...[
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: GestureDetector(
                                  onTap: () {
                                    bufferAlarmReference.color = color;
                                    state.setState();
                                  },
                                  child: CircleAvatar(
                                    backgroundColor: color,
                                    radius: 20,
                                    child: color.value == bufferAlarmReference.color.value ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Position', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(bufferAlarmReference.position.toSexagesimal(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Align(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            await navigateToAlarm(bufferAlarmReference);
                          },
                          icon: const Icon(Icons.navigate_next_rounded, color: Colors.white),
                          label: const Text('Go To Alarm', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Radius / Size (in meters)', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                      Text(bufferAlarmReference.radius.toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: Colors.redAccent, width: 2),
                              ),
                            ),
                            onPressed: () {
                              var ok = deleteAlarmById(alarmId);
                              if (!ok) {
                                debugPrintError('Alarm $id could not be deleted.');
                              }
                              // In case this alarm we just deleted happens to be the closest alarm, we need to make sure it doesn't show up.
                              state.closestAlarm = null;
                              Navigator.pop(context);
                            },
                            child: const Text('Delete Alarm', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void resetEditAlarmState() {
  var state = June.getState(() => LocaAlertState());
  state.bufferAlarm = null;
  state.nameInputController.clear();
  state.setState();
}
