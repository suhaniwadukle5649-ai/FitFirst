import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:health/health.dart';
import 'package:location/location.dart' as loc;
import 'package:lottie/lottie.dart' hide Marker;
import 'package:orka_sports/app/widgets/common_buttons_textforms/button_textforms.dart';
import 'package:orka_sports/core/constants/app_colors.dart';
import 'package:orka_sports/core/services/road_service.dart';
import 'package:orka_sports/core/utils/custom_smooth_navigation.dart';
import 'package:orka_sports/data/models/activity_model/activity_model.dart';
import 'package:orka_sports/data/repositories/activity_repository.dart';
import 'package:orka_sports/presentation/blocs/activity/activity_bloc.dart';
import 'package:orka_sports/presentation/blocs/activity_list/activity_list_bloc.dart';
import 'package:orka_sports/presentation/blocs/activity_list/activity_list_event.dart';
import 'package:orka_sports/presentation/blocs/activity_subcategory/activity_subcategory_bloc.dart';
import 'package:orka_sports/presentation/blocs/location/location_event.dart';
import 'package:orka_sports/presentation/blocs/profile/profile_bloc.dart';
import 'package:orka_sports/presentation/blocs/location/location_bloc.dart';
import 'package:orka_sports/presentation/blocs/location/location_state.dart' as AppLocationState;
import 'package:orka_sports/presentation/view/body/gear_screen/gear_screen.dart';
import 'package:orka_sports/presentation/view/body/nutrition_screen/nutrition_screen.dart';
import 'package:orka_sports/presentation/widgets/show_customsnackbar.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../history_screen/TaskScreen.dart';
import '../history_screen/history_screen.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

class KalmanFilter {
  double _q = 0.0001;
  double _r = 0.01;
  double _p = 1;
  double _x = 0;
  double _k = 0;
  bool _initialized = false;

  double filter(double measurement) {
    if (!_initialized) {
      _x = measurement;
      _initialized = true;
      return _x;
    }
    _p = _p + _q;
    _k = _p / (_p + _r);
    _x = _x + _k * (measurement - _x);
    _p = (1 - _k) * _p;
    return _x;
  }

  void reset() {
    _p = 1;
    _x = 0;
    _k = 0;
    _initialized = false;
  }
}

class ActivitySessionScreen extends StatefulWidget {
  final String activityType;
  final dynamic activityIcon;
  final String activityId;
  final String yourGoal;
  final double distanceGoal;
  final ActivityRepository activityRepo;

  const ActivitySessionScreen({
    super.key,
    required this.activityType,
    required this.activityIcon,
    required this.activityId,
    required this.yourGoal,
    required this.distanceGoal,
    required this.activityRepo,
  });

  @override
  State<ActivitySessionScreen> createState() => _ActivitySessionScreenState();
}

class _ActivitySessionScreenState extends State<ActivitySessionScreen> {
  bool isStarted = false;
  double distanceGoal = 3.5;
  String goalType = 'Distance';
  final List<String> goalTypes = ['Distance', 'Time'];
  int _currentIndex = 0;
  DateTime? _startTime;
  Timer? _activityTimer;
  int _durationSeconds = 0;
  double _currentHeading = 0.0;
  final loc.Location _locationController = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  final Completer<GoogleMapController> _mapCompleter =
  Completer<GoogleMapController>();
  GoogleMapController? _mapController;
  LatLng? _initialMapCenter;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _routeCoordinates = [];
  List<LatLng> _roadSnappedCoordinates = [];
  String _sourceLat = "0.0";
  String _sourceLng = "0.0";
  String _destinationLat = "0.0";
  String _destinationLng = "0.0";
  bool _isPaused = false;
  bool _isPausing = false;
  DateTime? _pauseStartTime;
  int _totalPausedSeconds = 0;
  double _liveGpsDistanceKm = 0.0;
  String _avgPace = "00:00";
  String _liveCalculatedCaloriesBurned = "0.0";
  double _maxSpeed = 0.0;
  int _overSpeedingCount = 0;
  double _totalElevationGain = 0.0;
  double _lastElevation = 0.0;
  double _weight = 70.0;
  bool _isStopping = false;
  bool _goalCompleted = false;
  final KalmanFilter _latFilter = KalmanFilter();
  final KalmanFilter _lngFilter = KalmanFilter();
  LatLng? _lastValidPosition;
  int _stationaryCount = 0;
  double _lastValidSpeed = 0.0;
  double _currentMapBearing = 0.0;
  double _currentGpsHeading = 0.0;
  StreamSubscription<StepCount>? _pedometerSubscription;
  int _sessionSteps = 0;
  int _stepsAtLastResume = -1;
  bool _stepPermissionGranted = false;
  StreamSubscription? _headingSubscription;
  MapType _currentMapType = MapType.normal;
  double _sw = 390.0;
  double _s(double base) => base * (_sw / 390.0);
  double _f(double base) => base * (_sw / 390.0);
  int _mapIndex = 0;

  final List<MapType> _mapTypes = [
    MapType.normal,
    MapType.satellite,
    MapType.hybrid,
    MapType.terrain,
  ];

  @override
  void initState() {
    super.initState();
    context.read<ActivityListBloc>().add(LoadActivityList());
    _requestPermissions();
    _startHeadingListener();
    _fastTrackLocation();
    log('ActivitySessionScreen initialized with activity Id: ${widget.activityId}');

    final locationBlocState = context.read<LocationBloc>().state;
    if (locationBlocState is AppLocationState.LocationLoaded) {
      _initialMapCenter =
          LatLng(locationBlocState.latitude, locationBlocState.longitude);
      _updateUserMarker(_initialMapCenter!);
    } else {
      context.read<LocationBloc>().add(FetchLocationEvent());
    }

    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      final weightString = profileState.profile.weight;
      if (weightString != null && weightString.isNotEmpty) {
        _weight = double.tryParse(weightString) ?? 70.0;
        log("User weight set from profile: $_weight kg");
      }
    } else {
      log("Profile not loaded at initState, using default weight: $_weight kg");
    }

    distanceGoal = (widget.distanceGoal == 0 || widget.distanceGoal == 0.0)
        ? 3.5
        : widget.distanceGoal;
  }

  Future<void> _fastTrackLocation() async {
    try {
      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted && _initialMapCenter == null) {
        setState(() {
          _initialMapCenter = LatLng(lastPos.latitude, lastPos.longitude);
        });
        _updateUserMarker(_initialMapCenter!);
      }

      // 2. Fir Current Position lo (Yeh thoda time leti hai par accurate hoti hai)
      Position currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _initialMapCenter = LatLng(currentPos.latitude, currentPos.longitude);
        });
        _updateUserMarker(_initialMapCenter!);
        
        // Map ko move karo agar mil gayi hai
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_initialMapCenter!, 15.0),
          );
        }
      }
    } catch (e) {
      log("Fast track location error: $e");
    }
  }

  void _startHeadingListener() {
    _headingSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null && mounted) {
        setState(() {
          _currentHeading = event.heading!;
        });
        if (_initialMapCenter != null) {
          _updateUserMarker(_initialMapCenter!);
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    bool serviceEnabled = await _locationController.serviceEnabled();
    final activityStatus = await Permission.activityRecognition.request();
    _stepPermissionGranted = activityStatus.isGranted;

    try {
      final types = [HealthDataType.STEPS];
      await Health().requestAuthorization(types);
    } catch (e) {
      log("Health permissions error: $e");
    }

    if (!serviceEnabled) {
      serviceEnabled = await _locationController.requestService();
      if (!serviceEnabled) {
        if (mounted) showCustomSnackbar(context, "Location service is disabled.");
      }
    }

    loc.PermissionStatus permissionStatus =
    await _locationController.hasPermission();
    if (permissionStatus == loc.PermissionStatus.denied) {
      permissionStatus = await _locationController.requestPermission();
      if (permissionStatus != loc.PermissionStatus.granted) {
        if (mounted) showCustomSnackbar(context, "Location permissions are denied.");
      }
    }

    await _locationController.changeSettings(
      accuracy: loc.LocationAccuracy.navigation,
      interval: 1000,
      distanceFilter: 3,
    );
  }

  void _onStepCount(StepCount event) {
    if (!isStarted) return;

    if (_isPaused) {
      _stepsAtLastResume = event.steps;
      return;
    }

    if (_stepsAtLastResume == -1) {
      _stepsAtLastResume = event.steps;
      return;
    }

    int delta = event.steps - _stepsAtLastResume;
    if (delta > 0 && delta < 50) {
      setState(() {
        _sessionSteps += delta;
        _stepsAtLastResume = event.steps;
      });
      log("Steps Update: $_sessionSteps");
    } else if (delta >= 50) {
      _stepsAtLastResume = event.steps;
      log("Steps Jump detected and ignored: $delta");
    }
  }

  void _onStepCountError(error) {
    log("Pedometer error: $error");
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!_mapCompleter.isCompleted) {
      _mapCompleter.complete(controller);
    }
    _mapController = controller;
    if (_initialMapCenter != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: _initialMapCenter!, zoom: 15.0),
            ),
          );
        }
      });
    }
  }

  Future<void> _updateUserMarker(LatLng position) async {
    final icon = await _buildDirectionalMarker(_currentHeading);

    final marker = Marker(
      markerId: const MarkerId('user_location'),
      position: position,
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      rotation: 0,
    );

    if (mounted) {
      setState(() {
        _markers
          ..removeWhere((m) => m.markerId.value == 'user_location')
          ..add(marker);
      });
    }
  }

  void _startActivityTimer() {
    _activityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_isPaused) return;
      setState(() {
        _durationSeconds++;
      });
    });
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  double _calculateCaloriesBurned(
      double distanceKm, int durationSeconds, double weight)
  {
    if (distanceKm <= 0.01) return 0;
    double met = 0.0;
    switch (widget.activityType) {
      case 'Walking': met = 3.5; break;
      case 'Running': met = 9.8; break;
      case 'Cycling': met = 7.5; break;
      case 'Hiking':  met = 6.0; break;
      default:        met = 3.5;
    }
    double durationHours = durationSeconds / 3600;
    return met * weight * durationHours;
  }

  void _checkOverspeeding(double currentSpeed) {
    double speedLimit = 0.0;
    switch (widget.activityType) {
      case 'Walking': speedLimit = 6.0;  break;
      case 'Running': speedLimit = 20.0; break;
      case 'Cycling': speedLimit = 30.0; break;
      default:        speedLimit = 6.0;
    }
    if (currentSpeed > speedLimit) _overSpeedingCount++;
  }

  Future<void> _checkGoalCompletion() async {
    if (!_goalCompleted && _liveGpsDistanceKm >= distanceGoal) {
      setState(() { _goalCompleted = true; });
      await _stopSession();
      log("Goal completed! Distance: $_liveGpsDistanceKm km / Goal: $distanceGoal km");
      _activityTimer?.cancel();
      _locationSubscription?.cancel();
      _showGoalCompletedDialog();
    }
  }

  Future<void> _showGoalCompletedDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: _s(24), vertical: _s(40)),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_s(28)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.18),
                  blurRadius: _s(32),
                  offset: Offset(0, _s(12)),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(_s(28)),
                      topRight: Radius.circular(_s(28)),
                    ),
                  ),
                  padding: EdgeInsets.symmetric(vertical: _s(28), horizontal: _s(20)),
                  child: Column(
                    children: [
                      Container(
                        width: _s(72), height: _s(72),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('🏆', style: TextStyle(fontSize: _f(38))),
                        ),
                      ),
                      SizedBox(height: _s(14)),
                      Text(
                        'Goal Completed!',
                        style: TextStyle(
                          color: Colors.white, fontSize: _f(24),
                          fontWeight: FontWeight.bold, letterSpacing: _s(0.5),
                        ),
                      ),
                      SizedBox(height: _s(6)),
                      Text(
                        'Amazing work! You crushed your target.',
                        style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: _f(14)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(_s(20), _s(22), _s(20), _s(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _goalStatChip(
                        icon: Icons.flag_rounded, color: Colors.green,
                        label: 'Goal', value: '${distanceGoal.toStringAsFixed(1)} km',
                      ),
                      Container(width: 1, height: _s(40), color: Colors.grey.shade200),
                      _goalStatChip(
                        icon: Icons.location_on_rounded, color: AppColors.primary,
                        label: 'Covered', value: '${_liveGpsDistanceKm.toStringAsFixed(2)} km',
                      ),
                      Container(width: 1, height: _s(40), color: Colors.grey.shade200),
                      _goalStatChip(
                        icon: Icons.local_fire_department_rounded, color: Colors.orange,
                        label: 'Calories', value: '$_liveCalculatedCaloriesBurned kcal',
                      ),
                    ],
                  ),
                ),
                Divider(height: _s(24), indent: _s(20), endIndent: _s(20)),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: _s(20)),
                  padding: EdgeInsets.symmetric(horizontal: _s(14), vertical: _s(7)),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(_s(20)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.activityIcon, size: _s(17), color: AppColors.primary),
                      SizedBox(width: _s(6)),
                      Text(
                        widget.activityType,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600, fontSize: _f(14),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: _s(22)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _s(20)),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity, height: _s(50),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary, elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(_s(16)),
                            ),
                          ),
                          onPressed: _isStopping ? null : () async {
                            setState(() => _isStopping = true);
                            await _stopSession();
                            if (mounted) {
                              setState(() => _isStopping = false);
                              CustomSmoothNavigator.push(
                                context,
                                TaskScreen(
                                  activityType: widget.activityType,
                                  activityIcon: widget.activityIcon,
                                  distanceCovered: _liveGpsDistanceKm,
                                  durationFormatted: _formatDuration(_durationSeconds - _totalPausedSeconds),
                                  caloriesBurned: _liveCalculatedCaloriesBurned,
                                  avgPace: _avgPace,
                                  steps: _sessionSteps,
                                  elevationGain: _totalElevationGain.toStringAsFixed(1),
                                  overSpeedingCount: _overSpeedingCount,
                                  routeCoordinates: _roadSnappedCoordinates.isNotEmpty
                                      ? _roadSnappedCoordinates
                                      : _routeCoordinates,
                                  markers: _markers,
                                  polylines: _polylines,
                                  startLatLng: _initialMapCenter,
                                ),
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bar_chart_rounded, color: Colors.white, size: _s(20)),
                              SizedBox(width: _s(8)),
                              Text(
                                'See Activity',
                                style: TextStyle(
                                  color: Colors.white, fontSize: _f(16),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: _s(10)),
                      SizedBox(
                        width: double.infinity, height: _s(46),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(_s(16)),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Continue Activity',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: _f(15), fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: _s(22)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _goalStatChip({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: _s(20)),
        SizedBox(height: _s(4)),
        Text(value, style: TextStyle(fontSize: _f(13), fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(label, style: TextStyle(fontSize: _f(11), color: Colors.black45)),
      ],
    );
  }

  Future<void> _showStartCountdown() async {
    int countdown = 5;
    Timer? countdownTimer;
    unawaited(_locationController.getLocation().catchError((e) => log("Pre-fetch error: $e")));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (countdown > 1) {
                if (mounted) setDialogState(() => countdown--);
              } else {
                timer.cancel();
                Navigator.of(dialogContext).pop();
                _startSession();
              }
            });

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: EdgeInsets.all(_s(24)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_s(30)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: _s(20),
                      spreadRadius: _s(5),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Get Ready!",
                      style: TextStyle(
                        fontSize: _f(22),
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: _s(20)),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: _s(120),
                          width: _s(120),
                          child: CircularProgressIndicator(
                            value: countdown / 5,
                            strokeWidth: _s(8),
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                        Text(
                          "$countdown",
                          style: TextStyle(
                            fontSize: _f(54),
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _s(25)),
                    Text(
                      "Fetching GPS Location...",
                      style: TextStyle(
                        fontSize: _f(14),
                        color: Colors.black45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startSession() async {
    log(">>> START SESSION CALLED for: ${widget.activityType}");
    setState(() {
      isStarted = true;
      _startTime = DateTime.now();
      _durationSeconds = 0;
      _liveGpsDistanceKm = 0.0;
      _routeCoordinates.clear();
      _roadSnappedCoordinates.clear();
      _markers.clear();
      _polylines.clear();
      _avgPace = "00:00";
      _liveCalculatedCaloriesBurned = "0.0";
      _overSpeedingCount = 0;
      _totalElevationGain = 0.0;
      _lastElevation = 0.0;
      _maxSpeed = 0.0;
      _isPaused = false;
      _isPausing = false;
      _pauseStartTime = null;
      _totalPausedSeconds = 0;
      _goalCompleted = false;
      _lastValidPosition = null;
      _stationaryCount = 0;
      _lastValidSpeed = 0.0;
      _latFilter.reset();
      _lngFilter.reset();
      _currentMapBearing = 0.0;
      _currentGpsHeading = 0.0;

      _sessionSteps = 0;
      _stepsAtLastResume = -1;
    });

    _startActivityTimer();

    if (_stepPermissionGranted) {
      _pedometerSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );
    }

    try {
      // Is call mein ab zyada time nahi lagega kyunki pre-fetch ho chuka hai
      loc.LocationData? currentLocation = await _locationController.getLocation();
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        _sourceLat = currentLocation.latitude!.toString();
        _sourceLng = currentLocation.longitude!.toString();
        final startLatLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);
        _routeCoordinates.add(startLatLng);
        _lastValidPosition = startLatLng;
        _latFilter.filter(currentLocation.latitude!);
        _lngFilter.filter(currentLocation.longitude!);
        _addMarker(startLatLng, "start_marker", "Start Point");
        _updateUserMarker(startLatLng);
        final controller = await _mapCompleter.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: startLatLng, zoom: 18, tilt: 45, bearing: 0),
          ),
        );
        setState(() {
          _currentGpsHeading = currentLocation.heading ?? 0.0;
        });
      }
    } catch (e) {
      if (mounted) showCustomSnackbar(context, "Could not get start location: $e");
    }

    double maxExpectedDistancePerUpdate;
    switch (widget.activityType) {
      case 'Walking': maxExpectedDistancePerUpdate = 15.0; break;
      case 'Running': maxExpectedDistancePerUpdate = 40.0; break;
      case 'Cycling': maxExpectedDistancePerUpdate = 80.0; break;
      case 'Hiking':  maxExpectedDistancePerUpdate = 20.0; break;
      default:        maxExpectedDistancePerUpdate = 15.0;
    }

    _locationSubscription = _locationController.onLocationChanged
        .listen((loc.LocationData newLocation) async {
      if (_isPaused) return;
      if (!mounted) return;

      if (newLocation.latitude == null ||
          newLocation.longitude == null ||
          newLocation.accuracy == null) return;

      if (newLocation.accuracy! > 18.0) return;

      final filteredLat = _latFilter.filter(newLocation.latitude!);
      final filteredLng = _lngFilter.filter(newLocation.longitude!);
      final filteredLatLng = LatLng(filteredLat, filteredLng);

      final double rawSpeed = (newLocation.speed != null && newLocation.speed! > 0)
          ? newLocation.speed! * 3.6
          : 0.0;

      if (rawSpeed < 1.8) {
        _stationaryCount++;
        if (_stationaryCount >= 3) return;
      } else {
        _stationaryCount = 0;
      }

      _lastValidSpeed = rawSpeed;

      if (_lastValidPosition == null) {
        _lastValidPosition = filteredLatLng;
        _updateUserMarker(filteredLatLng);
        return;
      }

      final double segmentDistance = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        filteredLatLng.latitude,
        filteredLatLng.longitude,
      );

      if (segmentDistance < 5.0) return;

      if (segmentDistance > maxExpectedDistancePerUpdate) return;

      _lastValidPosition = filteredLatLng;
      _updateUserMarker(filteredLatLng);

      setState(() {
        _liveGpsDistanceKm += segmentDistance / 1000.0;
        _checkOverspeeding(rawSpeed);
        if (rawSpeed > _maxSpeed) _maxSpeed = rawSpeed;
        if (newLocation.altitude != null) {
          final double currentElevation = newLocation.altitude!;
          if (_lastElevation > 0 && currentElevation > _lastElevation + 0.5) {
            _totalElevationGain += (currentElevation - _lastElevation);
          }
          _lastElevation = currentElevation;
        }
        _routeCoordinates.add(filteredLatLng);
        _destinationLat = filteredLat.toString();
        _destinationLng = filteredLng.toString();
        final int activeSeconds = _durationSeconds - _totalPausedSeconds;
        _avgPace = _liveGpsDistanceKm > 0
            ? _formatPace(_liveGpsDistanceKm, activeSeconds)
            : "0.00";
        _liveCalculatedCaloriesBurned = _calculateCaloriesBurned(
          _liveGpsDistanceKm,
          activeSeconds,
          _weight,
        ).toStringAsFixed(1);
        _currentGpsHeading = newLocation.heading ?? 0.0;
      });

      _checkGoalCompletion();

      if (_routeCoordinates.length % 5 == 0) {
        try {
          final snappedPoints = await RoadService.snapToRoads(_routeCoordinates);
          if (mounted) {
            setState(() {
              _roadSnappedCoordinates = snappedPoints;
              _updatePolyline();
            });
          }
        } catch (e) {
          setState(() {
            _roadSnappedCoordinates = List.from(_routeCoordinates);
            _updatePolyline();
          });
        }
      } else {
        _updatePolyline();
      }

      try {
        final controller = await _mapCompleter.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: filteredLatLng,
              zoom: 18,
              tilt: 45,
              bearing: newLocation.heading ?? 0,
            ),
          ),
        );
      } catch (e) {
        log("Camera animate error: $e");
      }
    });
  }

  void _addMarker(LatLng position, String markerId, String title) {
    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user_location');
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          infoWindow: InfoWindow(title: title),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            markerId == "start_marker" ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
        ),
      );
    });
  }

  Future<void> _togglePause() async {
    if (_isPausing) return;
    _isPausing = true;
    _stationaryCount = 0;
    try {
      if (_isPaused) {
        if (_pauseStartTime != null) {
          _totalPausedSeconds += DateTime.now().difference(_pauseStartTime!).inSeconds;
          _pauseStartTime = null;
        }
        _isPaused = false;
        _stepsAtLastResume = -1;
        _stationaryCount = 0;
        setState(() {});
      } else {
        _pauseStartTime = DateTime.now();
        _isPaused = true;
        setState(() {});
      }
    } catch (e) {
      log("Pause/Resume error: $e");
    } finally {
      if (mounted) {
        _isPausing = false;
        setState(() {});
      }
    }
  }

  void _updatePolyline() {
    if (!mounted) return;
    final coordinatesToUse = _roadSnappedCoordinates.isNotEmpty
        ? _roadSnappedCoordinates
        : _routeCoordinates;
    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: List<LatLng>.from(coordinatesToUse),
          color: AppColors.primary,
          width: _s(5).toInt(),
        ),
      );
    });
  }

  Future<void> _stopSession() async {
    if (_isPaused && _pauseStartTime != null) {
      _totalPausedSeconds += DateTime.now().difference(_pauseStartTime!).inSeconds;
      _pauseStartTime = null;
    }
    _isPaused = false;
    _activityTimer?.cancel();
    _locationSubscription?.cancel();
    _pedometerSubscription?.cancel();
    try {
      loc.LocationData? finalLocation = await _locationController.getLocation();
      if (finalLocation.latitude != null && finalLocation.longitude != null) {
        _destinationLat = finalLocation.latitude!.toString();
        _destinationLng = finalLocation.longitude!.toString();
        final finalLatLng = LatLng(finalLocation.latitude!, finalLocation.longitude!);
        if (_routeCoordinates.isNotEmpty && _routeCoordinates.last != finalLatLng) {
          _routeCoordinates.add(finalLatLng);
        }
        _addMarker(finalLatLng, "end_marker", "End Point");
      }
    } catch (e) {
      log("Error getting final location: $e");
    }
    
    int activeDurationSeconds = _durationSeconds - _totalPausedSeconds;
    if (activeDurationSeconds < 0) activeDurationSeconds = 0;
    double finalDistanceKm = _liveGpsDistanceKm;
    String finalCaloriesBurned = _calculateCaloriesBurned(
      finalDistanceKm, activeDurationSeconds, _weight,
    ).toStringAsFixed(1);
    String finalAvgPace = _formatPace(finalDistanceKm, activeDurationSeconds);
    String formattedDuration = _formatDuration(activeDurationSeconds);
    String formattedElevation = _totalElevationGain.toStringAsFixed(1);
    final userId = await SharedPreferences.getInstance()
        .then((prefs) => prefs.getString('userId'));
    if (userId == null) return;
    String? apiActivityId = widget.activityId;
    if (apiActivityId.isEmpty) return;
    _totalPausedSeconds = 0;
    final activityToSave = ActivityData(
      activityId: apiActivityId,
      activityName: widget.activityType,
      userId: userId,
      sourceLat: _sourceLat,
      sourceLng: _sourceLng,
      destinationLat: _destinationLat,
      destinationLng: _destinationLng,
      timeTaken: formattedDuration,
      distance: finalDistanceKm.toStringAsFixed(3),
      avgPace: finalAvgPace,
      overSpeeding: _overSpeedingCount > 0 ? "true" : "false",
      caloriesBurned: finalCaloriesBurned,
      elevationGain: formattedElevation,
      stepCount: _sessionSteps.toString(),
    );
    if (mounted) {
      context.read<ActivityBloc>().add(AddActivity(activityToSave));
      await _handleRewardLogic(finalActualDistance: finalDistanceKm);
    }
  }

  Future<void> _handleRewardLogic({required double finalActualDistance}) async {
    try {
      if (widget.activityType == "Walking") {
        final value = await widget.activityRepo.getDailyWalkRecommendation(actualDistance: finalActualDistance);
        await _showCoinsAwardedDialog(value.coinsAwardedToday, value.popupRequired);
      } else if (widget.activityType == "Running") {
        final value = await widget.activityRepo.getDailyRunRecommendation(actualDistance: finalActualDistance);
        await _showCoinsAwardedDialog(value.coinsAwardedToday, value.popupRequired);
      } else if (widget.activityType == "Cycling") {
        final value = await widget.activityRepo.getDailyCyclingRecommendation(actualDistance: finalActualDistance);
        await _showCoinsAwardedDialog(value.coinsAwardedToday, value.popupRequired);
      } else if (widget.activityType == "Hiking") {
        final value = await widget.activityRepo.getDailyHikingRecommendation(actualDistance: finalActualDistance);
        await _showCoinsAwardedDialog(value.coinsAwardedToday, value.popupRequired);
      }
    } catch (e) {
      log("Reward logic error: $e");
    }
  }

  Future<void> _showCoinsAwardedDialog(int coinsAwarded, bool popup) async {
    if (!mounted) return;
    if (coinsAwarded == 0) {
      await showGoalRestrictionPopup(context, distanceGoal.toString());
    } else {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(16))),
          title: Text("🎉 Congratulations!", style: TextStyle(fontSize: _f(18))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: _s(120), width: _s(120), child: Image.asset("assets/images/coin1.png")),
              SizedBox(height: _s(12)),
              Text("You have been awarded", style: TextStyle(fontSize: _f(14))),
              SizedBox(height: _s(8)),
              Text(
                "$coinsAwarded ${coinsAwarded < 10 ? "Coin" : "Coins"}",
                style: TextStyle(fontSize: _f(28), fontWeight: FontWeight.bold, color: AppColors.kPrimaryColor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Close", style: TextStyle(fontSize: _f(14))),
            ),
          ],
        ),
      );
    }
  }

  String _formatPace(double distanceKm, int durationSeconds) {
    if (distanceKm <= 0 || durationSeconds <= 0) return "0.00";
    double paceMinutesPerKm = (durationSeconds / 60.0) / distanceKm;
    return paceMinutesPerKm.toStringAsFixed(2);
  }

  void incrementGoalDistance() {
    setState(() => distanceGoal += 0.5);
  }

  void decrementGoalDistance() => setState(() {
    if (widget.distanceGoal == 0 || widget.distanceGoal == 0.0) {
      if (distanceGoal > 0.5) distanceGoal -= 0.5;
    } else {
      if (distanceGoal > widget.distanceGoal) {
        distanceGoal -= 0.5;
      } else {
        showGoalRestrictionPopup(context, distanceGoal.toString());
      }
    }
  });

  @override
  void dispose() {
    _activityTimer?.cancel();
    _locationSubscription?.cancel();
    _pedometerSubscription?.cancel();
    _headingSubscription?.cancel();
    if (_mapCompleter.isCompleted) {
      _mapController?.dispose();
    }
    super.dispose();
  }

  Future<void> showGoalRestrictionPopup(BuildContext context, String distanceGoal) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(20))),
          backgroundColor: AppColors.kWhite,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: _s(24.0), horizontal: _s(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Increase Goal",
                  style: TextStyle(fontSize: _f(18), color: AppColors.kPrimaryColor, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: _s(12)),
                Text(
                  "Kindly increase your goal to more than ${widget.distanceGoal} Km if you want to take part in the Fit First monthly rewards program and earn additional points on maintaining monthly streaks",
                  style: TextStyle(color: AppColors.kBlack, fontSize: _f(14), height: 1.4),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: _s(24)),
                Row(
                  children: [
                    Expanded(
                      child: ButtonWidget(
                        text: "Cancel",
                        borderRadius: BorderRadius.circular(_s(15)),
                        backgroundColor: WidgetStatePropertyAll(AppColors.kPrimaryColor),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.kWhite, fontWeight: FontWeight.bold,
                          fontSize: _f(16),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getDirectionLabel(double heading) {
    // Standardize heading to 0-360
    double h = heading % 360;
    if (h < 0) h += 360;
    
    if (h >= 337.5 || h < 22.5) return 'North';
    if (h >= 22.5 && h < 67.5) return 'North-East';
    if (h >= 67.5 && h < 112.5) return 'East';
    if (h >= 112.5 && h < 157.5) return 'South-East';
    if (h >= 157.5 && h < 202.5) return 'South';
    if (h >= 202.5 && h < 247.5) return 'South-West';
    if (h >= 247.5 && h < 292.5) return 'West';
    if (h >= 292.5 && h < 337.5) return 'North-West';
    return 'North';
  }


  @override
  Widget build(BuildContext context) {
    _sw = MediaQuery.of(context).size.width;
    return BlocListener<ActivityBloc, ActivityState>(
      listener: (context, state) {
        if (state is ActivityLoading) {
          showCustomSnackbar(context, 'Saving activity...');
        } else if (state is ActivityAddedSuccess) {
          showCustomSnackbar(context, state.response.message);
          setState(() {
            isStarted = false;
            _isStopping = false;
          });

          CustomSmoothNavigator.push(
            context,
            TaskScreen(
              activityType: widget.activityType,
              activityIcon: widget.activityIcon,
              distanceCovered: _liveGpsDistanceKm,
              durationFormatted: _formatDuration(_durationSeconds - _totalPausedSeconds),
              caloriesBurned: _liveCalculatedCaloriesBurned,
              avgPace: _avgPace,
              steps: _sessionSteps,
              elevationGain: _totalElevationGain.toStringAsFixed(1),
              overSpeedingCount: _overSpeedingCount,
              routeCoordinates: _roadSnappedCoordinates.isNotEmpty
                  ? _roadSnappedCoordinates
                  : _routeCoordinates,
              markers: _markers,
              polylines: _polylines,
              startLatLng: _initialMapCenter,
            ),
          );
        } else if (state is ActivityOperationFailure) {
          showCustomSnackbar(context, 'Error: ${state.error}');
          setState(() => _isStopping = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black, size: _s(24)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            "Activity",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: _f(18)),
          ),
          centerTitle: true,
        ),
        backgroundColor: Colors.white,
        body: SafeArea(
          child: _currentIndex == 0
              ? Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              final screenHeight = mq.size.height;
              final mapHeight = isStarted
                  ? screenHeight * 0.5
                  : screenHeight * 0.5;

              return Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: mapHeight,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(_s(20)),
                            bottomRight: Radius.circular(_s(20)),
                          ),
                          child: BlocListener<LocationBloc, AppLocationState.LocationState>(
                            listener: (context, locState) {
                              if (locState is AppLocationState.LocationLoaded && mounted) {
                                final newCenter = LatLng(locState.latitude, locState.longitude);
                                _updateUserMarker(newCenter);
                                if (_mapController != null) {
                                  _mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(target: newCenter, zoom: 15.0),
                                    ),
                                  );
                                } else {
                                  setState(() { _initialMapCenter = newCenter; });
                                }
                              }
                            },
                            child: _initialMapCenter != null
                                ? GoogleMap(
                              onMapCreated: _onMapCreated,
                              mapType: _currentMapType,
                              initialCameraPosition: CameraPosition(
                                target: _initialMapCenter!, zoom: 15.0,
                              ),
                              onCameraMove: (position) {
                                setState(() {
                                  _currentMapBearing = position.bearing;
                                });
                              },
                              markers: Set<Marker>.from(_markers),
                              polylines: Set<Polyline>.from(_polylines),
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              buildingsEnabled: false,
                              compassEnabled: false,
                              mapToolbarEnabled: false,
                              padding: EdgeInsets.only(bottom: _s(8)),
                            )
                                : Container(
                              color: Colors.grey.shade100,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: _s(2.5),
                                  ),
                                  SizedBox(height: _s(12)),
                                  Text(
                                    'Fetching location...',
                                    style: TextStyle(
                                      fontSize: _f(13),
                                      color: Colors.black45,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: _s(12),
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: _s(14), vertical: _s(6)),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(_s(20)),
                              border: Border.all(color: Colors.white24, width: _s(1)),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: _s(4))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.layers_rounded, color: Colors.white, size: _s(14)),
                                SizedBox(width: _s(6)),
                                Text(
                                  "${_currentMapType.name[0].toUpperCase()}${_currentMapType.name.substring(1)} Mode",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: _f(11),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (isStarted)
                        Positioned(
                          bottom: _s(-140),
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _buildGaugeOnly(context),
                          ),
                        ),

                      Positioned(
                        top: _s(14),
                        left: _s(14),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                context.read<ActivitySubCategoryBloc>().add(
                                  LoadSubCategories(
                                    activityId: widget.activityId,
                                    activityType: 'Nutrition',
                                  )
                                );
                                CustomSmoothNavigator.push(
                                  context,
                                  NutritionScreen(activityId: widget.activityId, activityType: 'Nutrition'),
                                );
                              },
                              child: Container(
                                height: _s(44),
                                width: _s(44),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: _s(8),
                                      offset: Offset(0, _s(2)),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.restaurant_menu, color: AppColors.primary, size: _s(22)),
                              ),
                            ),
                            SizedBox(height: _s(4)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _s(8), vertical: _s(3)),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(_s(10)),
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: _s(4))],
                              ),
                              child: Text('Nutrition',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _f(9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: _s(12)),
                            GestureDetector(
                              onTap: () {
                                context.read<ActivitySubCategoryBloc>().add(
                                  LoadSubCategories(activityId: widget.activityId, activityType: 'Gear'),
                                );
                                CustomSmoothNavigator.push(
                                  context,
                                  GearScreen(activityId: widget.activityId, activityType: 'Gear'),
                                );
                              },
                              child: Container(
                                height: _s(44),
                                width: _s(44),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: _s(8),
                                      offset: Offset(0, _s(2)),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.sports_martial_arts, color: AppColors.primary, size: _s(22)),
                              ),
                            ),
                            SizedBox(height: _s(4)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _s(8), vertical: _s(3)),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(_s(10)),
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: _s(4))],
                              ),
                              child: Text('Gears',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _f(9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Positioned(
                        top: _s(14),
                        right: _s(14),
                        child: Column(
                          children: [
                            // 1. Compass
                            GestureDetector(
                              onTap: () async {
                                if (_mapController != null && (_lastValidPosition != null || _initialMapCenter != null)) {
                                  await _mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: _lastValidPosition ?? _initialMapCenter!,
                                        zoom: 18,
                                        tilt: 45,
                                        bearing: 0,
                                      ),
                                    ),
                                  );
                                  setState(() {
                                    _currentMapBearing = 0.0;
                                  });
                                }
                              },
                              child: Container(
                                height: _s(44),
                                width: _s(44),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade300, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: _s(8),
                                      offset: Offset(0, _s(2)),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.rotate(
                                      angle: -(_currentMapBearing * (math.pi / 180)),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Icon(Icons.navigation, color: Colors.red, size: _s(26)),
                                          Transform.rotate(
                                            angle: math.pi,
                                            child: Icon(Icons.navigation, color: Colors.grey.shade400, size: _s(26)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: _s(3), height: _s(3),
                                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: _s(4)),

                            // 2. Direction Label
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _s(8), vertical: _s(3)),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(_s(10)),
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: _s(4))],
                              ),
                              child: Text(
                                _getDirectionLabel(_currentGpsHeading),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _f(9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(height: _s(12)),

                            // 3. My Location
                            GestureDetector(
                              onTap: () {
                                if (_mapController != null && _initialMapCenter != null) {
                                  _mapController!.animateCamera(
                                    CameraUpdate.newLatLngZoom(_initialMapCenter!, 17.0),
                                  );
                                }
                              },
                              child: Container(
                                width: _s(40), height: _s(40),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade500, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(.10),
                                      blurRadius: _s(8), offset: Offset(0, _s(2)),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.my_location_rounded, size: _s(18), color: Colors.black54),
                              ),
                            ),
                            SizedBox(height: _s(10)),

                            // 4. Zoom Controls
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(_s(10)),
                                border: Border.all(color: Colors.grey.shade500, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.10),
                                    blurRadius: _s(8), offset: Offset(0, _s(2)),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      if (_mapController != null) {
                                        final currentZoom = await _mapController!.getZoomLevel();
                                        _mapController!.animateCamera(
                                          CameraUpdate.newCameraPosition(
                                            CameraPosition(
                                              target: _lastValidPosition ?? _initialMapCenter!,
                                              zoom: (currentZoom + 1).clamp(3.0, 21.0),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: _s(36), height: _s(36),
                                      child: Icon(Icons.add, size: _s(18), color: Colors.black54),
                                    ),
                                  ),
                                  Container(width: _s(24), height: 0.5, color: Colors.grey.shade200),
                                  GestureDetector(
                                    onTap: () async {
                                      if (_mapController != null) {
                                        final currentZoom = await _mapController!.getZoomLevel();
                                        _mapController!.animateCamera(
                                          CameraUpdate.newCameraPosition(
                                            CameraPosition(
                                              target: _lastValidPosition ?? _initialMapCenter!,
                                              zoom: (currentZoom - 1).clamp(3.0, 21.0),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: _s(36), height: _s(36),
                                      child: Icon(Icons.remove, size: _s(18), color: Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: _s(20)),

                            // 5. Map Type Switcher
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _mapIndex = (_mapIndex + 1) % _mapTypes.length;
                                  _currentMapType = _mapTypes[_mapIndex];
                                });
                              },
                              child: Container(
                                height: _s(42),
                                width: _s(42),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade500, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.layers_sharp,
                                  color: AppColors.primary,
                                  size: _s(32),
                                ),
                              ),
                            ),
                            SizedBox(height: _s(4)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _s(8), vertical: _s(3)),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(_s(10)),
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: _s(4))],
                              ),
                              child: Text('Maps',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _f(9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (isStarted) SizedBox(height: _s(120)),
                  Expanded(
                    child: isStarted
                        ? _buildInProgressUI(context)
                        : _buildGoalUI(context),
                  ),
                ],
              );

            },
          )
              : HistoryScreen(activityType: widget.activityType),
        ),

        bottomNavigationBar: Builder(
          builder: (context) {
            final screenWidth = _sw;
            final hPad = _s(16);
            final vPad = _s(12);
            final btnHeight = _s(54);
            final fontSize = _f(18);
            final borderRadius = _s(16);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_currentIndex == 0)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    child: isStarted
                        ? _isPaused
                        ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: btnHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.green.shade700, Colors.green.shade500],
                              ),
                              borderRadius: BorderRadius.circular(borderRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(.35),
                                  blurRadius: _s(10), offset: Offset(0, _s(5)),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(borderRadius),
                                ),
                              ),
                              onPressed: (_isPausing || _isStopping) ? null : _togglePause,
                              icon: _isPausing
                                  ? SizedBox(
                                height: _s(20), width: _s(20),
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: _s(2.5),
                                ),
                              )
                                  : Icon(Icons.play_arrow_rounded, size: _s(24)),
                              label: Text(
                                'Resume',
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: hPad * 0.5),

                        Expanded(
                          child: Container(
                            height: btnHeight,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(borderRadius),
                              border: Border.all(color: Colors.grey.shade300, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.08),
                                  blurRadius: _s(10), offset: Offset(0, _s(5)),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(borderRadius),
                                ),
                              ),
                              onPressed: _isStopping ? null : () async {
                                setState(() => _isStopping = true);
                                await _stopSession();
                                if (mounted) setState(() => _isStopping = false);
                              },
                              icon: _isStopping
                                  ? SizedBox(
                                height: _s(20), width: _s(20),
                                child: CircularProgressIndicator(
                                  color: Colors.black54, strokeWidth: _s(2.5),
                                ),
                              )
                                  : Icon(Icons.stop_rounded, size: _s(24)),
                              label: Text(
                                'Finish',
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                        : Container(
                      width: double.infinity,
                      height: btnHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primary.withOpacity(.75)],
                        ),
                        borderRadius: BorderRadius.circular(borderRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(.35),
                            blurRadius: _s(10), offset: Offset(0, _s(5)),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(borderRadius),
                          ),
                        ),
                        onPressed: (_isPausing || _isStopping) ? null : _togglePause,
                        icon: (_isPausing || _isStopping)
                            ? SizedBox(
                          height: _s(20), width: _s(20),
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: _s(2.5),
                          ),
                        )
                            : Icon(Icons.stop_rounded, size: _s(24)),
                        label: Text(
                          'Stop',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                        : Container(
                      width: double.infinity,
                      height: btnHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primary.withOpacity(.7)],
                        ),
                        borderRadius: BorderRadius.circular(borderRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(.35),
                            blurRadius: _s(10), offset: Offset(0, _s(5)),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(borderRadius),
                          ),
                        ),
                        onPressed: _showStartCountdown,
                        child: Text(
                          'Start',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                _buildBottomBar(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGaugeOnly(BuildContext context) {
    double progressValue = 0.0;
    if (goalType == 'Distance' && distanceGoal > 0) {
      progressValue = (_liveGpsDistanceKm / distanceGoal).clamp(0.0, 1.0);
    }

    return Container(
      height: _s(200),
      width: _s(200),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 100,
            showLabels: false,
            showTicks: false,
            startAngle: 150,
            endAngle: 30,
            axisLineStyle: AxisLineStyle(
              thickness: 0.1,
              cornerStyle: CornerStyle.bothCurve,
              color: Colors.grey[200],
              thicknessUnit: GaugeSizeUnit.factor,
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: progressValue * 100,
                cornerStyle: CornerStyle.bothCurve,
                width: 0.1,
                sizeUnit: GaugeSizeUnit.factor,
                color: const Color(0xFF24CF5F),
              ),
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                positionFactor: 0.1,
                angle: 90,
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.activityType.toUpperCase(),
                      style: TextStyle(
                        fontSize: _f(16),
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "${(progressValue * 100).toStringAsFixed(0)} %",
                      style: TextStyle(
                          fontSize: _f(36), fontWeight: FontWeight.bold),
                    ),
                    if (goalType == 'Distance')
                      Text(
                        "of ${distanceGoal.toStringAsFixed(2)} km",
                        style: TextStyle(
                            fontSize: _f(14), color: Colors.black45),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalUI(BuildContext context) {
    final sw = _sw;
    final sh = MediaQuery.of(context).size.height;

    final lottieHeight = _s(80);
    final cardPadding = _s(16);
    final goalFontSize = _f(14);
    final distanceFontSize = _f(36);
    final iconButtonSize = _s(32);
    final iconHPad = _s(20);
    final activityIconSize = _s(15);
    final btnFontSize = _f(12);
    final btnVertPad = _s(11);
    final spacingSmall = _s(8);
    final spacingMed = _s(14);
    final hPad = _s(16);

    String lottiePath = "assets/Lottie/Running.json";
    if (widget.activityType.toLowerCase().contains("cycling")) {
      lottiePath = "assets/Lottie/Cycling.json";
    } else if (widget.activityType.toLowerCase().contains("hiking")) {
      lottiePath = "assets/Lottie/Hiking.json";
    } else if (widget.activityType.toLowerCase().contains("walking")) {
      lottiePath = "assets/Lottie/Walking.json";
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(26), topRight: Radius.circular(26),
        ),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            SizedBox(height: spacingSmall),
            SizedBox(height: lottieHeight, child: Lottie.asset(lottiePath, repeat: true)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Card(
                elevation: _s(6),
                shadowColor: Colors.black.withOpacity(.12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(22))),
                child: Padding(
                  padding: EdgeInsets.all(cardPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        widget.yourGoal,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: goalFontSize, letterSpacing: _s(1.2),
                        ),
                      ),
                      SizedBox(height: spacingMed),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.remove_circle, size: iconButtonSize, color: Colors.grey),
                            onPressed: decrementGoalDistance,
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: iconHPad),
                            child: Text(
                              distanceGoal.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: distanceFontSize,
                                fontWeight: FontWeight.bold, color: AppColors.primary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, size: iconButtonSize, color: Colors.grey),
                            onPressed: incrementGoalDistance,
                          ),
                        ],
                      ),
                      SizedBox(height: spacingSmall),
                      // Row(
                      //   children: [
                      //     Expanded(
                      //       child: ElevatedButton.icon(
                      //         onPressed: () {
                      //           context.read<ActivitySubCategoryBloc>().add(
                      //               LoadSubCategories(
                      //                 activityId: widget.activityId,
                      //                 activityType: 'Nutrition',
                      //               )
                      //           );
                      //
                      //           CustomSmoothNavigator.push(
                      //             context,
                      //             NutritionScreen(activityId: widget.activityId, activityType: 'Nutrition'),
                      //           );
                      //         },
                      //         icon: Icon(Icons.restaurant_menu, size: activityIconSize),
                      //         label: Text('Nutrition', style: TextStyle(fontWeight: FontWeight.bold, fontSize: btnFontSize)),
                      //         style: ElevatedButton.styleFrom(
                      //           backgroundColor: AppColors.primary, elevation: 4,
                      //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      //           padding: EdgeInsets.symmetric(vertical: btnVertPad),
                      //         ),
                      //       ),
                      //     ),
                      //     SizedBox(width: sw * 0.035),
                      //     Expanded(
                      //       child: ElevatedButton.icon(
                      //         onPressed: () {
                      //           context.read<ActivitySubCategoryBloc>().add(
                      //             LoadSubCategories(activityId: widget.activityId, activityType: 'Gear'),
                      //           );
                      //           CustomSmoothNavigator.push(
                      //             context,
                      //             GearScreen(activityId: widget.activityId, activityType: 'Gear'),
                      //           );
                      //         },
                      //         icon: Icon(Icons.sports_martial_arts, size: activityIconSize),
                      //         label: Text('Gears', style: TextStyle(fontWeight: FontWeight.bold, fontSize: btnFontSize)),
                      //         style: ElevatedButton.styleFrom(
                      //           backgroundColor: AppColors.primary, elevation: 4,
                      //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      //           padding: EdgeInsets.symmetric(vertical: btnVertPad),
                      //         ),
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      // SizedBox(height: spacingSmall),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: sh * 0.015),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCell({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    bool isLarge = false,
  })
  {
    final valueFontSize = isLarge ? _f(24) : _f(16);
    final iconSize = isLarge ? _s(22) : _s(16);
    final labelFontSize = isLarge ? _f(12) : _f(11);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(fontSize: valueFontSize, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ),
          SizedBox(height: _s(4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: iconSize),
              SizedBox(width: _s(4)),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: labelFontSize, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressUI(BuildContext context) {
    final hPad = _s(16);
    final rowSpacing2 = _s(25);
    Widget expandedView = Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell(
                  icon: Icons.location_on,
                  iconColor: Colors.orange,
                  value: _liveGpsDistanceKm.toStringAsFixed(3),
                  label: 'km',
                ),
                VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
                _buildStatCell(
                  icon: Icons.timer,
                  iconColor: Colors.blue,
                  value: _formatDuration(_durationSeconds),
                  label: 'Duration',
                  isLarge: true,
                ),
                VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
                _buildStatCell(
                  icon: Icons.directions_walk_outlined,
                  iconColor: Colors.brown,
                  value: '$_sessionSteps',
                  label: 'Steps Counter',
                ),
              ],
            ),
          ),
          SizedBox(height: rowSpacing2),
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell(
                  icon: Icons.speed,
                  iconColor: Colors.green,
                  value: _avgPace,
                  label: 'min/km',
                ),
                VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
                _buildStatCell(
                  icon: Icons.height,
                  iconColor: Colors.purple,
                  value: '${_totalElevationGain.toStringAsFixed(1)} m',
                  label: 'Elevation',
                ),
                VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
                _buildStatCell(
                  icon: Icons.local_fire_department,
                  iconColor: Colors.red,
                  value: _liveCalculatedCaloriesBurned,
                  label: 'Cal',
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget collapsedView = Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: _s(8)),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatCell(
              icon: Icons.location_on,
              iconColor: Colors.orange,
              value: _liveGpsDistanceKm.toStringAsFixed(3),
              label: 'km',
            ),
            VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
            _buildStatCell(
              icon: Icons.timer,
              iconColor: Colors.blue,
              value: _formatDuration(_durationSeconds),
              label: 'Duration',
              isLarge: true,
            ),
            VerticalDivider(color: Colors.grey.shade200, width: _s(15)),
            _buildStatCell(
              icon: Icons.directions_walk_outlined,
              iconColor: Colors.brown,
              value: '$_sessionSteps',
              label: 'Steps Counter',
            ),
          ],
        ),
      ),
    );

    return _StatsExpandWidget(
      collapsedView: collapsedView,
      expandedView: expandedView,
      bottomBar: _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(_s(12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_s(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: _s(10),
            spreadRadius: _s(2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(20)),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: _f(12),
          ),
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.flash_on, size: _s(24)),
              label: 'Start',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history, size: _s(24)),
              label: 'History',
            ),
          ],
          onTap: (index) {
            if (!isStarted) {
              setState(() => _currentIndex = index);
            } else {
              showCustomSnackbar(
                context,
                "Please stop the current activity before switching tabs.",
              );
            }
          },
        ),
      ),
    );
  }
  
  Future<BitmapDescriptor> _buildDirectionalMarker(double heading) async {
    final size = _s(120.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final center = Offset(size / 2, size / 2);
    final dotRadius = _s(14.0);

    // ── Torch/cone of light ──────────────────────────────────────
    final torchPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        size * 0.48,
        [
          Colors.white.withOpacity(0.55),
          Colors.white.withOpacity(0.18),
          Colors.transparent,
        ],
        [0.0, 0.45, 1.0],
      );

    final torchPath = Path();
    torchPath.moveTo(center.dx, center.dy);

    // cone angle = 50 degrees each side
    final angleRad = heading * (math.pi / 180);
    final coneAngle = 28.0 * (math.pi / 180);
    final coneLength = size * 0.48;

    torchPath.lineTo(
      center.dx + coneLength * math.sin(angleRad - coneAngle),
      center.dy - coneLength * math.cos(angleRad - coneAngle),
    );

    // arc at cone tip
    torchPath.arcTo(
      Rect.fromCircle(center: center, radius: coneLength),
      angleRad - coneAngle - math.pi / 2,
      coneAngle * 2,
      false,
    );

    torchPath.lineTo(
      center.dx + coneLength * math.sin(angleRad + coneAngle),
      center.dy - coneLength * math.cos(angleRad + coneAngle),
    );

    torchPath.close();
    canvas.drawPath(torchPath, torchPaint);

    // ── Outer pulse ring ─────────────────────────────────────────
    canvas.drawCircle(
      center,
      dotRadius + _s(8),
      Paint()
        ..color = Colors.blue.withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );

    // ── White border ring ────────────────────────────────────────
    canvas.drawCircle(
      center,
      dotRadius + _s(2.5),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // ── Main blue dot ────────────────────────────────────────────
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = const Color(0xFF1A73E8)
        ..style = PaintingStyle.fill,
    );

    // ── Direction arrow inside dot ───────────────────────────────
    final arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = _s(2.5)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleRad);

    final arrowPath = Path();
    arrowPath.moveTo(0, _s(-7));       // tip (pointing up = north, rotated by heading)
    arrowPath.lineTo(_s(-4), _s(4));
    arrowPath.lineTo(0, _s(1));
    arrowPath.lineTo(_s(4), _s(4));
    arrowPath.close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}

class _StatsExpandWidget extends StatefulWidget {
  final Widget collapsedView;
  final Widget expandedView;
  final Widget bottomBar;

  const _StatsExpandWidget({
    required this.collapsedView,
    required this.expandedView,
    required this.bottomBar,
  });

  @override
  State<_StatsExpandWidget> createState() => _StatsExpandWidgetState();
}

class _StatsExpandWidgetState extends State<_StatsExpandWidget> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  OverlayEntry? _overlayEntry;
  AnimationController? _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOutCubic,
    ));
  }

  double _sw = 390.0;
  double _s(double base) => base * (_sw / 390.0);
  double _f(double base) => base * (_sw / 390.0);

  void _showOverlay(BuildContext outerContext) {
    if (_animationController == null) return;
    _sw = MediaQuery.of(outerContext).size.width;

    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _hideOverlay,
              child: FadeTransition(
                opacity: _animationController!,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),

            SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.92,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.vertical(top: Radius.circular(_s(32))),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: _s(30),
                        spreadRadius: _s(2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Container(
                          margin: EdgeInsets.only(top: _s(12), bottom: _s(4)),
                          width: _s(36),
                          height: _s(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(_s(10)),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(_s(20), _s(12), _s(20), _s(12)),
                          child: Row(
                            children: [
                              Container(
                                width: _s(10),
                                height: _s(10),
                                margin: EdgeInsets.only(right: _s(10)),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E676)
                                          .withOpacity(0.4),
                                      blurRadius: _s(6),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LIVE STATS',
                                      style: TextStyle(
                                        fontSize: _f(18),
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                        letterSpacing: 2.5,
                                      ),
                                    ),
                                    Text(
                                      'Real-time activity tracking',
                                      style: TextStyle(
                                        fontSize: _f(11),
                                        color: Colors.grey.shade600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: _hideOverlay,
                                child: Container(
                                  padding: EdgeInsets.all(_s(8)),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(_s(10)),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: _s(1),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.black87,
                                    size: _s(22),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),


                        Container(
                          height: _s(1),
                          margin: EdgeInsets.symmetric(horizontal: _s(20)),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF00E676).withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: _s(20)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: _s(20)),
                          child: Row(
                            children: [
                              Container(
                                width: _s(3),
                                height: _s(14),
                                margin: EdgeInsets.only(right: _s(8)),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(_s(2)),
                                ),
                              ),
                              Text(
                                'FEATURES',
                                style: TextStyle(
                                  fontSize: _f(11),
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: _s(14)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: _s(16)),
                          child: Container(
                            child: widget.expandedView,
                          ),
                        ),

                        SizedBox(height: _s(24)),
                        Container(
                          height: _s(1),
                          margin: EdgeInsets.symmetric(horizontal: _s(20)),
                          color: Colors.grey.shade200,
                        ),

                        SizedBox(height: _s(20)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: _s(20)),
                          child: Row(
                            children: [
                              Container(
                                width: _s(3),
                                height: _s(14),
                                margin: EdgeInsets.only(right: _s(8)),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF448AFF),
                                  borderRadius: BorderRadius.circular(_s(2)),
                                ),
                              ),
                              Text(
                                'MORE FUNCTIONS',
                                style: TextStyle(
                                  fontSize: _f(11),
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: _s(14)),
                        // Padding(
                        //   padding: EdgeInsets.symmetric(horizontal: _s(16)),
                        //   child: Row(
                        //     children: [
                        //       _moreFunctionPlaceholder(
                        //         icon: Icons.map_outlined,
                        //         label: 'Route Map',
                        //         color: const Color(0xFF448AFF),
                        //       ),
                        //       SizedBox(width: _s(10)),
                        //       _moreFunctionPlaceholder(
                        //         icon: Icons.favorite_outline,
                        //         label: 'Heart Rate',
                        //         color: const Color(0xFFFF4B6E),
                        //       ),
                        //       SizedBox(width: _s(10)),
                        //       _moreFunctionPlaceholder(
                        //         icon: Icons.music_note_outlined,
                        //         label: 'Music',
                        //         color: const Color(0xFFFF9800),
                        //       ),
                        //     ],
                        //   ),
                        // ),

                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey.shade200,
                                width: _s(1),
                              ),
                            ),
                          ),
                          child: widget.bottomBar,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(outerContext).insert(_overlayEntry!);
    _animationController?.forward();
    setState(() => _isExpanded = true);
  }

  Widget _moreFunctionPlaceholder({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: _s(16)),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(_s(16)),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: _s(22)),
            SizedBox(height: _s(8)),
            Text(
              label,
              style: TextStyle(
                fontSize: _f(11),
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: _s(4)),
            Text(
              'Soon',
              style: TextStyle(
                fontSize: _f(9),
                color: color.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideOverlay() async {
    if (_animationController != null) {
      await _animationController!.reverse();
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isExpanded = false);
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.collapsedView,

        if (!_isExpanded)
          Positioned(
            top: _s(-22),
            right: _s(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_s(12)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: _s(8),
                    offset: Offset(0, _s(4)),
                  ),
                ],
              ),
              child: Material(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(_s(12)),
                child: InkWell(
                  onTap: () => _showOverlay(context),
                  borderRadius: BorderRadius.circular(_s(12)),
                  child: Padding(
                    padding: EdgeInsets.all(_s(8)),
                    child: Icon(
                      Icons.open_in_full,
                      color: Colors.white,
                      size: _s(24),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}