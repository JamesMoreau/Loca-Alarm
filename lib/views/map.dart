import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:location_alarm/constants.dart';
import 'package:location_alarm/location_alarm_state.dart';
import 'package:location_alarm/main.dart';
import 'package:location_alarm/models/alarm.dart';

class MapView extends StatefulWidget {
	const MapView({super.key});

	@override
	State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
	@override
	Widget build(BuildContext context) {
		return GetBuilder<ProximityAlarmState>(
			builder: (state) {
				var statusBarHeight = MediaQuery.of(context).padding.top;
				var widthOfScreen = MediaQuery.of(context).size.width;

				// Display user's location on the map.
				var userLocationMarker = <Marker>[];
				if (state.userLocation != null)
					userLocationMarker.addAll([
						Marker(
							point: state.userLocation!,
							child: Icon(Icons.circle, color: Colors.blue),
						),
						Marker(
							point: state.userLocation!,
							child: Icon(Icons.person_rounded, color: Colors.white, size: 18),
						),
					]);

				// If no alarms are currently visible, show an arrow pointing towards the closest alarm (if there is one).
				var showClosestAlarmCompass = state.closestAlarm != null && !state.closestAlarmIsInView && state.showClosestOffScreenAlarm;
				Widget arrow = SizedBox.shrink();
				Widget compassAlarmIcon = SizedBox.shrink();

				var angle = 0.0;
				var alarmCompassSizePercentage = 0.9;
				var alarmCompassDisplayRadius = widthOfScreen * alarmCompassSizePercentage * (1 / 2);

				if (showClosestAlarmCompass) {
					// Arrow pointing upwards
					arrow = Icon(Icons.arrow_upward_rounded, color: state.closestAlarm!.color, size: 30);
					compassAlarmIcon = Icon(Icons.pin_drop_rounded, color: state.closestAlarm!.color, size: 30);

					// Calculate the angle between the center of the map and the closest alarm
					var centerOfMap = state.mapController.camera.center;
					angle = getAngleBetweenTwoPositions(centerOfMap, state.closestAlarm!.position);
				}

				// Display the alarms as circles on the map.
				var alarmCircles = <CircleMarker>[];
				var alarmMarkers = <Marker>[];
				if (state.showMarkersInsteadOfCircles) {
					// These are the same alarms as the circles, but they are markers instead. They are only visible when the user is zoomed out beyond circleToMarkerZoomThreshold.
					for (var alarm in state.alarms) {
						var marker = Marker(
							point: alarm.position,
							child: Icon(Icons.pin_drop_rounded, color: alarm.color, size: 30),
						);

						alarmMarkers.add(marker);
					}
				} else {
					for (var alarm in state.alarms) {
						var circle = CircleMarker(
							point: alarm.position,
							color: alarm.color.withOpacity(alarmColorOpacity),
							borderColor: alarmBorderColor,
							borderStrokeWidth: alarmBorderWidth,
							radius: alarm.radius,
							useRadiusInMeter: true,
						);

						alarmCircles.add(circle);
					}
				}

				// Overlay the alarm placement ui on top of the map. This is only visible when the user is placing an alarm.
				CircleMarker? alarmPlacementCircle;
				if (state.isPlacingAlarm) {
					var centerOfMap = LatLng(0, 0);
					centerOfMap = state.mapController.camera.center;
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
								initialCenter: LatLng(0, 0),
								initialZoom: initialZoom,
								interactionOptions: InteractionOptions(flags: myInteractiveFlags),
								keepAlive: true, // Keep the map alive when it is not visible.
								onMapEvent: myOnMapEvent,
								onMapReady: myOnMapReady,
							),
							children: [
                TileLayer(
                  urlTemplate: openStreetMapTemplateUrl,
                  userAgentPackageName: 'com.location_alarm.app',
                  tileProvider: CachedTileProvider(
                    maxStale: const Duration(days: 30),
                    store: state.mapTileCacheStore!,
                  ),
                ),
                if (state.showMarkersInsteadOfCircles) MarkerLayer(markers: alarmMarkers) else CircleLayer(circles: alarmCircles),
                if (alarmPlacementCircle != null) CircleLayer(circles: [alarmPlacementCircle]),
								MarkerLayer(markers: userLocationMarker),
							],
						),
						if (showClosestAlarmCompass) ...[
							// Display the arrow pointing towards the closest alarm.
							IgnorePointer(
								child: Center(
									child: Transform.translate(
										offset: Offset(alarmCompassDisplayRadius * sin(angle), -alarmCompassDisplayRadius * cos(angle)),
										child: Transform.rotate(
											angle: angle,
											child: arrow,
										),
									),
								),
							),
							IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: Offset((alarmCompassDisplayRadius - 30) * sin(angle), -(alarmCompassDisplayRadius - 30) * cos(angle)),
                    child: compassAlarmIcon,
                  ),
                ),
              ),
            ],
						Positioned(
							// Attribution to OpenStreetMap
							top: statusBarHeight + 5,
							child: Align(
								child: Container(
									padding: EdgeInsets.all(3),
									decoration: BoxDecoration(
										color: Colors.white.withOpacity(0.7),
										borderRadius: BorderRadius.circular(8),
									),
									child: Text(
										'© OpenStreetMap contributors',
									),
								),
							),
						),
						Positioned(
							// Place the alarm placement buttons in the top right corner.
							top: statusBarHeight + 10,
							right: 15,
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.end,
								mainAxisAlignment: MainAxisAlignment.spaceAround,
								children: [
                  FloatingActionButton(
                    onPressed: followOrUnfollowUserLocation,
                    elevation: 4,
                    child: Icon(state.followUserLocation ? Icons.lock_open_rounded : CupertinoIcons.location_fill),
                  ),
									SizedBox(height: 10),
									if (state.isPlacingAlarm) ...[
										// Show the confirm and cancel buttons when the user is placing an alarm.
										FloatingActionButton(
											onPressed: () {
												// Save alarm
												var centerOfMap = state.mapController.camera.center;
												var alarmPlacementPosition = centerOfMap;
												var alarm = createAlarm(name: 'Alarm', position: alarmPlacementPosition, radius: state.alarmPlacementRadius);
												addAlarm(alarm);
												resetAlarmPlacementUIState();
												state.update();
											},
											elevation: 4,
											child: Icon(Icons.check),
										),
										SizedBox(height: 10),
										FloatingActionButton(
											onPressed: () {
												resetAlarmPlacementUIState();
												state.update();
											},
											elevation: 4,
											child: Icon(Icons.cancel_rounded),
										),
									] else ...[
										// Show the place alarm button when the user is not placing an alarm.
										FloatingActionButton(
											onPressed: () {
												state.isPlacingAlarm = true;
												state.followUserLocation = false;
												state.update();
											},
											elevation: 4,
											child: Icon(Icons.pin_drop_rounded),
										),
									],
									SizedBox.shrink(),
								],
							),
						),
						if (state.isPlacingAlarm) // Show the slider to adjust the new alarm's radius.
							Positioned(
								bottom: 150,
								child: Container(
									width: MediaQuery.of(context).size.width * 0.9,
									decoration: BoxDecoration(
										color: Theme.of(context).colorScheme.primaryContainer,
										borderRadius: BorderRadius.all(Radius.circular(15)),
										boxShadow: [
											BoxShadow(
												color: Colors.grey.withOpacity(0.5),
												spreadRadius: 2,
												blurRadius: 5,
												offset: Offset(0, 3),
											),
										],
									),
									child: Padding(
										padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
										child: Row(
											children: [
												Text('Size:', style: TextStyle(fontWeight: FontWeight.bold)),
												Expanded(
													child: Slider(
														value: state.alarmPlacementRadius,
														onChanged: (value) {
															state.alarmPlacementRadius = value;
															state.update();
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
							SizedBox.shrink(),
					],
				);
			},
		);
	}

	@override
	void dispose() {
		resetAlarmPlacementUIState();
		super.dispose();
	}

	void myOnMapEvent(MapEvent event) {
		var las = Get.find<ProximityAlarmState>();

		var centerOfMap = las.mapController.camera.center;

		// Update the closest alarm stuff.
		var alarms = las.alarms;
		las.closestAlarm = getClosestAlarmToPosition(centerOfMap, alarms);

		// Update whether the closest alarm is in view.
		if (las.closestAlarm != null) {
			var cameraBounds = las.mapController.camera.visibleBounds;
			if (cameraBounds.contains(las.closestAlarm!.position))
				las.closestAlarmIsInView = true;
			else
				las.closestAlarmIsInView = false;
		}

		// If the user is zoomed out, show the alarms as markers instead of circles.
		if (las.mapController.camera.zoom < circleToMarkerZoomThreshold)
			las.showMarkersInsteadOfCircles = true;
		else
			las.showMarkersInsteadOfCircles = false;

		las.update();
	}

	Future<void> myOnMapReady() async {
		// Check location permission and request it if necessary.
		var permission = await Geolocator.checkPermission();
		if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
			await checkPermissionAndMaybeInitializeUserPositionStream();
			await moveMapToUserLocation();
			return; // the user has already granted location permissions.
		}

		if (permission == LocationPermission.denied) {
			// The user has denied location permissions. We can ask for them again.
			var permission = await Geolocator.requestPermission();
			if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
				await checkPermissionAndMaybeInitializeUserPositionStream();
				await moveMapToUserLocation();
			}
			return;
		}

		if (permission == LocationPermission.deniedForever) {
			debugPrint('Warning: User has denied location permissions forever.');
			ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
				SnackBar(
					behavior: SnackBarBehavior.floating,
					content: Container(
						padding: const EdgeInsets.all(8),
						child: Text('Location permissions are required to use this app.'),
					),
					action: SnackBarAction(label: 'Settings', onPressed: Geolocator.openAppSettings),
					shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
				),
			);
		}
	}

  void followOrUnfollowUserLocation() {
    var state = Get.find<ProximityAlarmState>();
    if (state.followUserLocation) {
      state.followUserLocation = false;
			state.update();
			return;
		}

		// Check if we actually can follow the user's location. If not, show a snackbar.
		if (state.userLocation == null) {
			debugPrint("Error: Unable to follow the user's location.");
			ScaffoldMessenger.of(NavigationService.navigatorKey.currentContext!).showSnackBar(
				SnackBar(
					behavior: SnackBarBehavior.floating,
					content: Container(
						padding: const EdgeInsets.all(8),
						child: Text('Unable to follow your location. Are location services permitted?'),
					),
					shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
				),
			);
			return;
		}

		state.followUserLocation = true;
		moveMapToUserLocation();
		state.update();
  }
}

Future<void> moveMapToUserLocation() async {
	var las = Get.find<ProximityAlarmState>();

	var userPosition = las.userLocation;
	if (userPosition == null) {
		debugPrint('Error: Unable to move map to user location.');
		return;
	}

	var currentZoom = las.mapController.camera.zoom;
	las.mapController.move(userPosition, currentZoom);

	debugPrint('Moving map to user location.');
}

double getAngleBetweenTwoPositions(LatLng from, LatLng to) {
	var angle = atan2(to.longitude - from.longitude, to.latitude - from.latitude);
	return angle;
}

Future<void> navigateToAlarm(Alarm alarm) async {
	var las = Get.find<ProximityAlarmState>();
	
	// Switch to the map view
	las.currentView = ProximityAlarmViews.map;
	las.update();
	las.pageController.jumpToPage(las.currentView.index);

	// Move the map to the alarm
	las.mapController.move(alarm.position, initialZoom);
}
