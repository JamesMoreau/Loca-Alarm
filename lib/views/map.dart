import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:june/june.dart';
import 'package:latlong2/latlong.dart';
import 'package:loca_alert/constants.dart';
import 'package:loca_alert/loca_alert_state.dart';
import 'package:loca_alert/main.dart';
import 'package:loca_alert/models/alarm.dart';
import 'package:location/location.dart';

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return JuneBuilder(
      () => LocaAlertState(),
      builder: (state) {
        var mapTileCacheStoreReference = state.mapTileCacheStore;
        if (mapTileCacheStoreReference == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        var statusBarHeight = MediaQuery.of(context).padding.top;
        var screenSize = MediaQuery.of(context).size;

        var userLocationReference = state.userLocation;
        var userLocationMarker = <Marker>[];
        if (userLocationReference != null)
          userLocationMarker.addAll([
            Marker(
              point: userLocationReference,
              child: const Icon(Icons.circle, color: Colors.blue),
            ),
            Marker(
              point: userLocationReference,
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
            ),
          ]);

        // If no alarms are currently visible on screen, show an arrow pointing towards the closest alarm (if there is one).
        var closestAlarmReference = state.closestAlarm;
        var arrow = const SizedBox.shrink() as Widget;
        var indicatorAlarmIcon = const SizedBox.shrink() as Widget;
        var angle = 0.0;
        var angleIs9to3 = false;
        var arrowRotation = 0.0;
        var ellipseWidth = screenSize.width * 0.8;
        var ellipseHeight = screenSize.height * 0.65;
        var closestAlarmName = '';

        var showClosestAlarmIndicator = closestAlarmReference != null && !state.closestAlarmIsInView && state.showClosestOffScreenAlarm;
        if (showClosestAlarmIndicator) {
          var indicatorColor = closestAlarmReference.color;
          arrow = Transform.rotate(angle: -pi / 2, child: Icon(Icons.arrow_forward_ios, color: indicatorColor, size: 28));
          indicatorAlarmIcon = Icon(Icons.pin_drop_rounded, color: indicatorColor, size: 32);

          var centerOfMap = state.mapController.camera.center;
          arrowRotation = angle = getAngleBetweenTwoPositions(centerOfMap, closestAlarmReference.position);
          angle = (arrowRotation + 3 * pi / 2) % (2 * pi); // Compensate the for y-axis pointing downwards on Transform.translate().
          angleIs9to3 = angle > (0 * pi) && angle < (1 * pi); // This is used to offset the text from the icon to not overlap with the arrow.

          closestAlarmName = closestAlarmReference.name;
        }

        // Display the alarms as circles or markers on the map. We create a set of markers or circles
        // representing the same alarms. The markers are only visible when the user is zoomed out
        // beyond (below) circleToMarkerZoomThreshold.
        var alarmCircles = <CircleMarker>[];
        var alarmMarkers = <Marker>[];
        if (state.showMarkersInsteadOfCircles) {
          for (var alarm in state.alarms) {
            var marker = Marker(
              width: 100,
              height: 65,
              point: alarm.position,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 100),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: paleBlue.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alarm.name,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            );

            alarmMarkers.add(marker);
          }
        } else {
          for (var alarm in state.alarms) {
            var circle = CircleMarker(
              point: alarm.position,
              color: alarm.color.withOpacity(0.5),
              borderColor: const Color(0xff2b2b2b),
              borderStrokeWidth: 2,
              radius: alarm.radius,
              useRadiusInMeter: true,
            );

            alarmCircles.add(circle);
          }
        }

        CircleMarker? alarmPlacementCircle;
        if (state.isPlacingAlarm) {
          var centerOfMap = state.mapController.camera.center;
          var alarmPlacementPosition = centerOfMap;
          alarmPlacementCircle = CircleMarker(
            point: alarmPlacementPosition,
            radius: state.alarmPlacementRadius,
            color: Colors.redAccent.withOpacity(0.5),
            borderColor: Colors.black,
            borderStrokeWidth: 2,
            useRadiusInMeter: true,
          );
        }

        // If the map is locked to the user's location, disable move interaction.
        var myInteractiveFlags = InteractiveFlag.all & ~InteractiveFlag.rotate;
        if (state.followUserLocation) myInteractiveFlags = myInteractiveFlags & ~InteractiveFlag.pinchMove & ~InteractiveFlag.drag & ~InteractiveFlag.flingAnimation;

        return Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              mapController: state.mapController,
              options: MapOptions(
                initialCenter: state.initialCenter ?? const LatLng(0,0),
                initialZoom: initialZoom,
                interactionOptions: InteractionOptions(flags: myInteractiveFlags),
                // keepAlive: true, // Keep the map alive when it is not visible. This uses more battery.
                onMapEvent: myOnMapEvent,
                onMapReady: myOnMapReady,
              ),
              children: [
                TileLayer(
                  urlTemplate: openStreetMapTemplateUrl,
                  userAgentPackageName: state.packageName,
                  tileProvider: CachedTileProvider(
                    maxStale: const Duration(days: 30),
                    store: mapTileCacheStoreReference,
                  ),
                ),
                if (state.showMarkersInsteadOfCircles) MarkerLayer(markers: alarmMarkers) else CircleLayer(circles: alarmCircles),
                if (alarmPlacementCircle != null) CircleLayer(circles: [alarmPlacementCircle]),
                if (state.userLocation != null) MarkerLayer(markers: userLocationMarker),
              ],
            ),
            if (showClosestAlarmIndicator) ...[
              IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: Offset((ellipseWidth / 2) * cos(angle), (ellipseHeight / 2) * sin(angle)),
                    child: Transform.rotate(
                      angle: arrowRotation,
                      child: arrow,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: Offset((ellipseWidth / 2 - 24) * cos(angle), (ellipseHeight / 2 - 24) * sin(angle)),
                    child: indicatorAlarmIcon,
                  ),
                ),
              ),
              if (closestAlarmName.isNotEmpty)
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset((ellipseWidth / 2 - 26) * cos(angle), (ellipseHeight / 2 - 26) * sin(angle)),
                      child: Transform.translate(
                        // Move the text up or down depending on the angle to now overlap with the arrow.
                        offset: angleIs9to3 ? const Offset(0, -22) : const Offset(0, 22),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 100),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: paleBlue.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            closestAlarmName,
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            // Attribution to OpenStreetMap
            Positioned(
              top: statusBarHeight + 5,
              child: IgnorePointer(
                child: Align(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors',
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: statusBarHeight + 10,
              right: 15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FloatingActionButton(
                    child: const Icon(Icons.info_outline_rounded),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext context) => Dialog(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.info_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 15),
                                const Text(
                                  'Here you can place new alarms by tapping the marker button. You can also follow / unfollow your location by tapping the lock button.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 15),
                                const Text('Staying on the map view for long periods of time may drain your battery.', textAlign: TextAlign.center),
                                const SizedBox(height: 15),
                                const Text(
                                  'Set location permissions to "While Using" or "Always" and enable notifications to use the app when running in background.',
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.followUserLocation) ...[
                    FloatingActionButton(
                      onPressed: followOrUnfollowUserLocation,
                      elevation: 4,
                      backgroundColor: const Color.fromARGB(255, 216, 255, 218),
                      child: const Icon(Icons.near_me_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: followOrUnfollowUserLocation,
                      elevation: 4,
                      child: const Icon(Icons.lock_rounded),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (state.isPlacingAlarm) ...[
                    FloatingActionButton(
                      onPressed: () {
                        var centerOfMap = state.mapController.camera.center;
                        var alarmPlacementPosition = centerOfMap;
                        var alarm = Alarm(name: 'Alarm', position: alarmPlacementPosition, radius: state.alarmPlacementRadius);
                        addAlarm(alarm);
                        resetAlarmPlacementUIState();
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.check),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      onPressed: () {
                        resetAlarmPlacementUIState();
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.cancel_rounded),
                    ),
                  ] else ...[
                    FloatingActionButton(
                      onPressed: () {
                        state.isPlacingAlarm = true;
                        state.followUserLocation = false;
                        state.setState();
                      },
                      elevation: 4,
                      child: const Icon(Icons.pin_drop_rounded),
                    ),
                  ],
                  const SizedBox.shrink(),
                ],
              ),
            ),
            if (state.isPlacingAlarm)
              Positioned(
                bottom: 150,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.all(Radius.circular(15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    child: Row(
                      children: [
                        const Text('Size:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Slider(
                            value: state.alarmPlacementRadius,
                            onChanged: (value) {
                              state.alarmPlacementRadius = value;
                              state.setState();
                            },
                            min: 100,
                            max: 3000,
                            divisions: 100,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  void myOnMapEvent(MapEvent event) {
    var state = June.getState(() => LocaAlertState());

    var centerOfMap = state.mapController.camera.center;

    var alarms = state.alarms;
    state.closestAlarm = getClosestAlarmToPosition(centerOfMap, alarms);

    var closestAlarmReference = state.closestAlarm;
    if (closestAlarmReference != null) {
      var cameraBounds = state.mapController.camera.visibleBounds;
      if (cameraBounds.contains(closestAlarmReference.position))
        state.closestAlarmIsInView = true;
      else
        state.closestAlarmIsInView = false;
    }

    if (state.mapController.camera.zoom < circleToMarkerZoomThreshold)
      state.showMarkersInsteadOfCircles = true;
    else
      state.showMarkersInsteadOfCircles = false;

    state.setState();
  }

  Future<void> myOnMapReady() async {
    var state = June.getState(() => LocaAlertState());
    
    var initialCenterReference = state.initialCenter;
    var shouldMoveToInitialCenter = initialCenterReference != null;
    if (shouldMoveToInitialCenter) {
      state.followUserLocation = false;
      state.mapController.move(initialCenterReference, state.mapController.camera.zoom);
      state.initialCenter = null;
      state.setState();
    }

    var serviceIsEnabled = await location.serviceEnabled();
    if (!serviceIsEnabled) {
      var newIsServiceEnabled = await location.requestService();
      if (!newIsServiceEnabled) {
        debugPrintError('Location services are not enabled.');
        return;
      }
    }

    var permission = await location.hasPermission();
    debugPrintInfo('Location permission status: $permission');

    // If the user has denied location permissions forever, we can't request them, so we show a snackbar.
    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      debugPrintWarning('User has denied location permissions.');
      ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: const EdgeInsets.all(8),
            child: const Text('Location permissions are required to use this app.'),
          ),
          action: SnackBarAction(label: 'Settings', onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.location)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      return;
    }

    // The remaining case is that the user has granted location permissions, so we do nothing.
  }

  void followOrUnfollowUserLocation() {
    var state = June.getState(() => LocaAlertState());
    if (state.followUserLocation) {
      state.followUserLocation = false;
      state.setState();
      return;
    }

    // Check if we actually can follow the user's location. If not, show a snackbar.
    if (state.userLocation == null) {
      debugPrintError("Unable to follow the user's location.");
      ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: const EdgeInsets.all(8),
            child: const Text('Unable to follow your location. Are location services permitted?'),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    state.followUserLocation = true;
    moveMapToUserLocation();
    state.setState();
  }
}

Future<void> moveMapToUserLocation() async {
  var state = June.getState(() => LocaAlertState());

  var currentViewIsMap = state.currentView != ProximityAlarmViews.map;
  if (currentViewIsMap) {
    return;
  }

  var userPosition = state.userLocation;
  if (userPosition == null) {
    debugPrintError('Unable to move map to user location.');
    return;
  }

  var currentZoom = state.mapController.camera.zoom;
  state.mapController.move(userPosition, currentZoom);

  debugPrintInfo('Moving map to user location.');
}

double getAngleBetweenTwoPositions(LatLng from, LatLng to) => atan2(to.longitude - from.longitude, to.latitude - from.latitude);

Future<void> navigateToAlarm(Alarm alarm) async {
  var state = June.getState(() => LocaAlertState());
  state.initialCenter = alarm.position;
  navigateToView(ProximityAlarmViews.map);
}
