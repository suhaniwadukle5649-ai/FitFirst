import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:orka_sports/app/widgets/common_buttons_textforms/button_textforms.dart';
import 'package:orka_sports/app/widgets/container/container.dart';
import 'package:orka_sports/core/constants/app_colors.dart';
import 'package:orka_sports/core/constants/app_sizes_paddings.dart';
import 'package:orka_sports/core/services/di_services.dart';
import 'package:orka_sports/core/utils/custom_smooth_navigation.dart';
import 'package:orka_sports/presentation/blocs/activity_subcategory/activity_subcategory_bloc.dart';
import 'package:orka_sports/presentation/view/body/gear_screen/gear_screen.dart';
import 'package:orka_sports/presentation/view/body/nutrition_screen/nutrition_screen.dart';
import 'package:orka_sports/presentation/view/gym/presentation/pages/gym.dart';
import 'package:orka_sports/presentation/view/gym/presentation/pages/gym_diet_tracking_screen.dart';
import 'package:orka_sports/presentation/view/gym/presentation/pages/gym_personalized_plan_screen.dart';
import 'package:orka_sports/presentation/view/scheduler_reminders/data/models/get_progress_model.dart';
import 'package:orka_sports/presentation/view/scheduler_reminders/data/models/get_today_workout_model.dart';
import 'package:orka_sports/presentation/view/scheduler_reminders/domain/entities/scheduler_entity.dart';
import 'package:orka_sports/presentation/view/scheduler_reminders/presentation/controllers/scheduler_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';


class GymDashboardScreen extends StatefulWidget {
  const GymDashboardScreen({super.key});


  @override
  State<GymDashboardScreen> createState() => _GymDashboardScreenState();
}


class _GymDashboardScreenState extends State<GymDashboardScreen> {
  String? partnerId;


  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback(
          (timeStamp) async {
        final schedulerController = ProviderScope.containerOf(context).read(DiProviders.schedulerControllerProvider.notifier);
        final gymController = ProviderScope.containerOf(context).read(DiProviders.gymControllerProvider.notifier);


        await gymController.checkGymVerificationStatus();
        schedulerController.startGreetingTimer();
        schedulerController.getWeeklyProgress(context);
        schedulerController.getTodayWorkOutSchedule(context);
        schedulerController.getFullSchedulerByDay(context);
        final prefs = await SharedPreferences.getInstance();
        final storedPartnerId = prefs.getString("partnerId");

        setState(() {
          partnerId = storedPartnerId;
        });

        print("Partner ID found: $storedPartnerId");

        if (storedPartnerId != null && storedPartnerId.isNotEmpty) {
          print("Loading gym buddies for partner: $storedPartnerId");
          gymController.getGymBuddy(context);
        } else {
          print("No partner ID found - user needs to select a gym");
        }
      },
    );
    super.initState();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final schedulerState = ref.watch(DiProviders.schedulerControllerProvider);
        final schedulerProvider = ref.read(DiProviders.schedulerControllerProvider.notifier);
        final weeklyProgress = schedulerState.getWeeklyProgressList.progress;
        final todayWorkOut = schedulerState.getTodayWorkOutList.data;
        final dailySchedule = schedulerState.getFullScheduleModel.data?.dailySchedule;


        return schedulerState.isWeeklyProgressLoading || schedulerState.isTodayWorkOutLoading || schedulerState.isAllScheduleLoading
            ? CommonLoadingWidget()
            : (weeklyProgress == null && todayWorkOut == null && dailySchedule == null)
            ? GymBoardingScreen()
            : GymResultScreen(
          schedulerState: schedulerState,
          weeklyProgress: weeklyProgress,
          todayWorkOut: todayWorkOut,
          schedulerController: schedulerProvider,
          partnerId: partnerId,
        );
      },
    );
  }
}

class GymResultScreen extends ConsumerWidget {
  const GymResultScreen({
    super.key,
    required this.schedulerState,
    required this.weeklyProgress,
    required this.todayWorkOut,
    required this.schedulerController,
    required this.partnerId,
  });

  final SchedulerEntity schedulerState;
  final Progress? weeklyProgress;
  final TodayWorkoutData? todayWorkOut;
  final SchedulerController schedulerController;
  final String? partnerId;

  String formatTimeTo12Hour(String time24) {
    if (time24.isEmpty) return '';
    try {
      final DateTime dateTime = DateTime.parse('2023-01-01 $time24:00');
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return time24;
    }
  }

  double _s(double base, double sw) => base * (sw / 390.0);
  double _f(double base, double sw) => base * (sw / 390.0);

  Widget _buildSelectGymContainer(BuildContext context, double sw) {
    return Container(
      padding: EdgeInsets.all(_s(16, sw)),
      decoration: BoxDecoration(
        color: AppColors.kWhite,
        borderRadius: BorderRadius.circular(_s(16, sw)),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: _s(10, sw)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.fitness_center, color: Colors.grey, size: _s(32, sw)),
          SizedBox(width: _s(12, sw)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Select Your Gym", style: TextStyle(fontWeight: FontWeight.w600, fontSize: _f(16, sw))),
                Text("Choose a gym to find workout buddies", style: TextStyle(color: Colors.grey, fontSize: _f(14, sw))),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              CustomSmoothNavigator.push(context, GymBoardingScreen());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kPrimaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(8, sw))),
            ),
            child: Text("Select Gym", style: TextStyle(fontSize: _f(13, sw))),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingContainer(double sw) {
    return Container(
      height: _s(100, sw),
      decoration: BoxDecoration(
        color: AppColors.kWhite,
        borderRadius: BorderRadius.circular(_s(16, sw)),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: _s(10, sw)),
        ],
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildNoBuddiesContainer(BuildContext context, gymProvider, double sw) {
    return Container(
      padding: EdgeInsets.all(_s(16, sw)),
      decoration: BoxDecoration(
        color: AppColors.kWhite,
        borderRadius: BorderRadius.circular(_s(16, sw)),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: _s(10, sw)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey,
            radius: _s(20, sw),
            child: Icon(Icons.person, color: Colors.white, size: _s(24, sw)),
          ),
          SizedBox(width: _s(12, sw)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("No gym buddies available", style: TextStyle(fontWeight: FontWeight.w600, fontSize: _f(14, sw))),
                Text("Be the first to join this gym!", style: TextStyle(color: Colors.grey, fontSize: _f(12, sw))),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              gymProvider.getGymBuddy(context); // Retry loading
            },
            child: Text("Refresh", style: TextStyle(fontSize: _f(14, sw))),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalBuddyList(gymState, BuildContext context, double sw) {
    return Container(
      height: _s(100, sw),
      decoration: BoxDecoration(
        color: AppColors.kWhite,
        borderRadius: BorderRadius.circular(_s(16, sw)),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: _s(10, sw)),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _s(16, sw), vertical: _s(12, sw)),
        itemCount: gymState.getGymBuddyList.data?.length ?? 0,
        itemBuilder: (context, index) {
          final buddy = gymState.getGymBuddyList.data?[index];
          final rating = double.tryParse(buddy?.avgRating ?? '0') ?? 0.0;

          return Container(
            width: _s(200, sw), // Shows ~3 at a time
            margin: EdgeInsets.only(right: _s(12, sw)),
            child: Row(
              children: [
                // Buddy Avatar
                CircleAvatar(
                  radius: _s(24, sw),
                  backgroundImage: (buddy?.image != null && buddy!.image!.isNotEmpty)
                      ? NetworkImage(buddy.image!)
                      : null,
                  backgroundColor: Colors.grey[300],
                  child: (buddy?.image == null || buddy!.image!.isEmpty)
                      ? Icon(Icons.person, size: _s(20, sw), color: Colors.grey)
                      : null,
                ),

                SizedBox(width: _s(12, sw)),

                // Buddy Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Name
                      Text(
                        buddy?.name ?? 'Unknown',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: _f(14, sw),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: _s(2, sw)),

                      Text(
                        "Age ${buddy?.age ?? '-'} • ${buddy?.fitnessLevel ?? 'Beginner'}",
                        style: TextStyle(
                          fontSize: _f(12, sw),
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      SizedBox(height: _s(4, sw)),

                      // Rating
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            color: rating >= 4.0 ? Colors.green :
                            rating >= 3.0 ? Colors.orange :
                            rating >= 1.0 ? Colors.red : Colors.grey,
                            size: _s(14, sw),
                          ),
                          SizedBox(width: _s(2, sw)),
                          Text(
                            rating > 0 ? rating.toStringAsFixed(1) : 'New',
                            style: TextStyle(
                              fontSize: _f(12, sw),
                              fontWeight: FontWeight.w600,
                              color: rating >= 4.0 ? Colors.green :
                              rating >= 3.0 ? Colors.orange :
                              rating >= 1.0 ? Colors.red : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sw = MediaQuery.of(context).size.width;
    final dailySchedule = schedulerState.getFullScheduleModel.data?.dailySchedule;

    final displayWorkout = (todayWorkOut?.workout != null && todayWorkOut!.workout!.isNotEmpty)
        ? todayWorkOut!.workout
        : dailySchedule?.workout;

    final displayFrom = (todayWorkOut?.workoutTimeFrom != null && todayWorkOut!.workoutTimeFrom!.isNotEmpty)
        ? todayWorkOut!.workoutTimeFrom
        : dailySchedule?.workoutTimeFrom;

    final displayTo = (todayWorkOut?.workoutTimeTo != null && todayWorkOut!.workoutTimeTo!.isNotEmpty)
        ? todayWorkOut!.workoutTimeTo
        : dailySchedule?.workoutTimeTo;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: RefreshIndicator.adaptive(
          onRefresh: () {
            return schedulerController.onRefreshGymSchedule(context);
          },
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_s(24, sw)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(schedulerState.greetingMessage, style: TextStyle(fontSize: _f(16, sw), fontWeight: FontWeight.w500)),
                          SizedBox(height: _s(4, sw)),
                          Text("Ready for today's workout?", style: TextStyle(fontSize: _f(24, sw), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: _s(24, sw)),
                schedulerState.isWeeklyProgressLoading || schedulerState.isTodayWorkOutLoading || schedulerState.isAllScheduleLoading
                    ? CommonLoadingWidget()
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Weekly Progress
                    Text("Weekly Progress",
                        style: TextStyle(fontSize: _f(16, sw), fontWeight: FontWeight.bold)),
                    SizedBox(height: _s(15, sw)),
                    Container(
                      padding: EdgeInsets.all(_s(16, sw)),
                      decoration: BoxDecoration(
                        color: AppColors.kWhite,
                        borderRadius: BorderRadius.circular(_s(16, sw)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            blurRadius: _s(10, sw),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            height: _s(60, sw),
                            width: _s(60, sw),
                            child: CircularProgressIndicator(
                              value: double.parse(weeklyProgress?.percentage ?? "0") / 100,
                              color: AppColors.kPrimaryColor,
                              backgroundColor: Colors.grey.shade300,
                              strokeWidth: _s(6, sw),
                            ),
                          ),
                          SizedBox(width: _s(16, sw)),
                          Expanded(
                            child: Text(
                                "${weeklyProgress?.completedDays} of ${weeklyProgress?.totalDays} workouts completed",
                                style: TextStyle(fontSize: _f(16, sw))),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: _s(15, sw)),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<ActivitySubCategoryBloc>().add(
                                LoadSubCategories(activityId: "28", activityType: 'Nutrition'),
                              );
                              CustomSmoothNavigator.push(
                                context,
                                NutritionScreen(activityId: "28", activityType: 'Nutrition'),
                              );
                            },
                            icon: Icon(Icons.restaurant_menu, color: Colors.white, size: _s(20, sw)),
                            label: Text('Nutrition',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: _f(16, sw))),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(14, sw))),
                              padding: EdgeInsets.symmetric(vertical: _s(14, sw)),
                            ),
                          ),
                        ),
                        SizedBox(width: _s(16, sw)),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<ActivitySubCategoryBloc>().add(
                                LoadSubCategories(activityId: "28", activityType: 'Gear'),
                              );
                              CustomSmoothNavigator.push(
                                context,
                                GearScreen(activityId: "28", activityType: 'Gear'),
                              );
                            },
                            icon: Icon(Icons.sports_martial_arts, color: Colors.white, size: _s(20, sw)),
                            label:
                            Text('Gears', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _f(16, sw))),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_s(14, sw))),
                              padding: EdgeInsets.symmetric(vertical: _s(14, sw)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _s(24, sw)),

                    Text("Workout Progress",
                        style: TextStyle(fontSize: _f(16, sw), fontWeight: FontWeight.bold)),
                    SizedBox(height: _s(15, sw)),
                    Container(
                      padding: EdgeInsets.all(_s(16, sw)),
                      decoration: BoxDecoration(
                        color: AppColors.kPrimaryColor,
                        borderRadius: BorderRadius.circular(_s(16, sw)),
                      ),
                      child: (displayWorkout == null || displayWorkout.isEmpty || displayWorkout == "Off today")
                          ? Center(
                              child: Text(
                                "Off Day - No workout scheduled for today",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: _f(14, sw)),
                              ),
                            )
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's Workout", style: TextStyle(color: AppColors.kWhite, fontSize: _f(14, sw))),
                          SizedBox(height: _s(6, sw)),
                          Text(displayWorkout,
                              style: TextStyle(
                                  fontSize: _f(22, sw), color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: _s(10, sw)),
                          Row(
                            children: [
                              Icon(Icons.access_time, color: Colors.white, size: _s(18, sw)),
                              SizedBox(width: _s(4, sw)),
                              Text(
                                  "${formatTimeTo12Hour(displayFrom ?? '')} - ${formatTimeTo12Hour(displayTo ?? '')}",
                                  style: TextStyle(color: Colors.white, fontSize: _f(14, sw))),
                            ],
                          ),
                          if (todayWorkOut?.buddyName != null && todayWorkOut!.buddyName!.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: _s(6, sw)),
                              child: Row(
                                children: [
                                  Icon(Icons.person, color: Colors.white, size: _s(18, sw)),
                                  SizedBox(width: _s(4, sw)),
                                  Text("with ${todayWorkOut?.buddyName ?? ''}",
                                      style: TextStyle(color: Colors.white, fontSize: _f(14, sw))),
                                ],
                              ),
                            ),
                          SizedBox(height: _s(16, sw)),
                          SizedBox(
                            width: double.infinity,
                            child: ButtonWidget(
                              text: "Mark as Complete",
                              borderRadius: BorderRadius.circular(_s(15, sw)),
                              backgroundColor: WidgetStatePropertyAll(AppColors.kWhite),
                              style: TextStyle(
                                color: AppColors.kPrimaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: _f(16, sw),
                              ),
                              onPressed: () async {
                                try {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => Center(
                                      child: CircularProgressIndicator(color: AppColors.kPrimaryColor),
                                    ),
                                  );


                                  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!serviceEnabled) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Location services are disabled.'), backgroundColor: Colors.red),
                                    );
                                    return;
                                  }


                                  LocationPermission permission = await Geolocator.checkPermission();
                                  if (permission == LocationPermission.denied) {
                                    permission = await Geolocator.requestPermission();
                                    if (permission == LocationPermission.denied) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Location permissions are denied.'), backgroundColor: Colors.red),
                                      );
                                      return;
                                    }
                                  }
                                  if (permission == LocationPermission.deniedForever) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Location permissions are permanently denied.'), backgroundColor: Colors.red),
                                    );
                                    return;
                                  }


                                  Position position = await Geolocator.getCurrentPosition();


                                  final prefs = await SharedPreferences.getInstance();
                                  final String? userIdStr = prefs.getString("userId");
                                  if (userIdStr == null) {
                                    Navigator.pop(context);
                                    throw Exception("User ID not found.");
                                  }
                                  int userId = int.tryParse(userIdStr) ?? 0;


                                  String currentDay = DateFormat('EEEE').format(DateTime.now());


                                  final data = {
                                    "user_id": userId,
                                    "day": currentDay,
                                    "latitude": position.latitude,
                                    "longitude": position.longitude,
                                  };


                                  print("Mark complete request: $data");


                                  final response = await Dio().post(
                                    "https://fitfirst.online/Service/markWorkoutComplete",
                                    data: data,
                                  );


                                  Navigator.pop(context);


                                  final respData = response.data;
                                  if (respData["status"] == "success") {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("${respData["message"]} 🎉 Coins awarded: ${respData["coins_awarded_today"]}"),
                                        backgroundColor: Colors.green,
                                      ),
                                    );

                                    schedulerController.onRefreshGymSchedule(context);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(respData["message"] ?? "Failed to mark workout complete"),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Error marking workout complete: $e"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _s(24, sw)),

                    Text("Workout Buddies",
                        style: TextStyle(fontSize: _f(16, sw), fontWeight: FontWeight.bold)),
                    SizedBox(height: _s(15, sw)),
                    partnerId == null || partnerId!.isEmpty
                        ? _buildSelectGymContainer(context, sw)
                        : Consumer(
                      builder: (context, ref, child) {
                        final gymState = ref.watch(DiProviders.gymControllerProvider);
                        final gymProvider = ref.watch(DiProviders.gymControllerProvider.notifier);

                        print("Gym state loading: ${gymState.isGymBuddyLoading}"); // ✅ DEBUG LOG
                        print("Gym buddies count: ${gymState.getGymBuddyList.data?.length ?? 0}"); // ✅ DEBUG LOG

                        if (gymState.isGymBuddyLoading) {
                          return _buildLoadingContainer(sw);
                        }

                        if (gymState.getGymBuddyList.data?.isEmpty ?? true) {
                          return _buildNoBuddiesContainer(context, gymProvider, sw);
                        }

                        return _buildHorizontalBuddyList(gymState, context, sw);
                      },
                    ),

                    SizedBox(height: _s(16, sw)),
                    Consumer(
                      builder: (context, ref, child) {
                        final gymState = ref.watch(DiProviders.gymControllerProvider);

                        print("🔍 DEBUG: isGymCodeVerified = ${gymState.isGymCodeVerified}");

                        // Show locked state if not verified
                        if (!gymState.isGymCodeVerified) {
                          print("🔒 Showing locked state");
                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(_s(16, sw)),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(_s(15, sw)),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.lock, color: Colors.grey[600], size: _s(32, sw)),
                                SizedBox(height: _s(8, sw)),
                                Text(
                                  "Complete Gym Registration",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                    fontSize: _f(16, sw),
                                  ),
                                ),
                                SizedBox(height: _s(4, sw)),
                                Text(
                                  "Join a gym first to unlock your personalized plan",
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: _f(14, sw),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        print("✅ Showing active button");

                        return SizedBox(
                          width: double.infinity,
                          child: ButtonWidget(
                            text: "Get My Personalised Plan",
                            borderRadius: BorderRadius.circular(_s(15, sw)),
                            backgroundColor: WidgetStatePropertyAll(AppColors.kWhite),
                            side: BorderSide(color: AppColors.kPrimaryColor),
                            style: TextStyle(
                                color: AppColors.kPrimaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: _f(16, sw)
                            ),
                            onPressed: () async {
                              print("✅ Button clicked! Starting personalised plan process...");

                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => Center(
                                  child: CircularProgressIndicator(color: AppColors.kPrimaryColor),
                                ),
                              );

                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final String userId = prefs.getString("userId") ?? "";

                                print("User ID: $userId");

                                if (userId.isEmpty) {
                                  throw Exception("User not logged in");
                                }

                                String doshaResult = "vata";

                                final bodyIqState = ref.read(DiProviders.bodyIqControllerProvider);
                                final doshaResultModel = bodyIqState.getDoshaResultModel;

                                if (doshaResultModel?.dominantDosha != null) {
                                  doshaResult = doshaResultModel!.dominantDosha!.toLowerCase();
                                  print("Dosha retrieved from model: $doshaResult");
                                } else {
                                  print("Using fallback dosha value: $doshaResult");
                                }

                                Navigator.pop(context);

                                print("✅ Navigating to GymPersonalizedPlanScreen...");

                                CustomSmoothNavigator.push(
                                    context,
                                    GymPersonalizedPlanScreen(
                                      userId: userId,
                                      doshaResult: doshaResult,
                                      foodType: 2,
                                    )
                                );

                              } catch (e) {
                                Navigator.pop(context);

                                print("❌ Error: $e");

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AppColors.kRed,
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      },
                    ),

                    SizedBox(height: _s(24, sw)),
                    CommonContainerWithBorder(
                      radius: _s(10, sw),
                      child: Column(
                        children: [
                          Text("Want to reset gym steps & workouts?", style: TextStyle(fontSize: _f(14, sw))),
                          SizedBox(height: _s(10, sw)),
                          SizedBox(
                            width: double.infinity,
                            child: ButtonWidget(
                              text: "Reset Gym Steps",
                              borderRadius: BorderRadius.circular(_s(15, sw)),
                              backgroundColor: WidgetStatePropertyAll(AppColors.kWhite),
                              side: BorderSide(
                                color: AppColors.kPrimaryColor,
                              ),
                              style: TextStyle(
                                color: AppColors.kPrimaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: _f(16, sw),
                              ),
                              onPressed: () {
                                CustomSmoothNavigator.push(context, GymBoardingScreen());
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _s(32, sw)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
