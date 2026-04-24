import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orka_sports/app/widgets/appbar/appbar.dart';
import 'package:orka_sports/app/widgets/common_buttons_textforms/button_textforms.dart';
import 'package:orka_sports/app/widgets/common_dropdowns/common_dropdowns.dart';
import 'package:orka_sports/core/constants/app_colors.dart';
import 'package:orka_sports/core/constants/app_sizes_paddings.dart';
import 'package:orka_sports/data/repositories/schedule_repository.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../core/services/di_services.dart';
import 'dashborad/gym_dashboad.dart';

class AddExerciseScheduleScreen extends ConsumerStatefulWidget {
  final String userId;
  final String doshaResult;

  const AddExerciseScheduleScreen({
    super.key,
    required this.userId,
    required this.doshaResult,
  });

  @override
  ConsumerState<AddExerciseScheduleScreen> createState() =>
      _AddExerciseScheduleScreenState();
}

class _AddExerciseScheduleScreenState
    extends ConsumerState<AddExerciseScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  final ScheduleRepository _scheduleRepo = ScheduleRepository();
  String selectedDay = '';
  List<String> selectedWorkouts = [];
  TimeOfDay? fromTime;
  TimeOfDay? toTime;
  bool _isLoading = false;
  bool _isLoadingSchedule = false;
  bool _isEditMode = false;
  String? _existingScheduleId;
  bool isWorkoutReminderEnabled = false;
  bool isLoadingReminder = false;
  Map<String, dynamic>? weeklySchedule;
  final List<String> workoutOptions = [
    'Chest Exercises',
    'Back Exercises',
    'Shoulder Exercises',
    'Biceps Exercises',
    'Triceps Exercises',
    'Leg Exercises',
    'Calf Exercises',
    'Ab & Core Exercises',
    'Cardio Machines',
    'Full-Body / Functional Movements',
    'Bodyweight Exercises',
    'CrossFit/HIIT Style Movements',
  ];

  @override
  void initState() {
    super.initState();
    loadWeeklySchedule();
    _initializeWorkoutReminders();
  }

  void _updateWeeklyCard() {
    if (selectedDay.isEmpty) return;

    setState(() {
      weeklySchedule ??= {
        "workouts": {},
        "fromTimes": {},
        "toTimes": {},
      };

      weeklySchedule!["workouts"][selectedDay] = selectedWorkouts;
      weeklySchedule!["fromTimes"][selectedDay] =
          fromTime?.format(context) ?? "";
      weeklySchedule!["toTimes"][selectedDay] =
          toTime?.format(context) ?? "";
    });
  }

  Future<void> loadWeeklySchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("weekly_schedule");

    if (data != null) {
      setState(() {
        weeklySchedule = jsonDecode(data);
      });
    }
  }

  Future<void> _initializeWorkoutReminders() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'workout_reminders',
          channelName: 'Workout Reminders',
          channelDescription: 'Notifications for workout time',
          defaultColor: AppColors.kPrimaryColor,
          ledColor: AppColors.kPrimaryColor,
          importance: NotificationImportance.High,
        ),
      ],
    );
  }

  Future<void> _pickTime(
      BuildContext context, ValueChanged<TimeOfDay> onSelected,
      {TimeOfDay? initial}) async
  {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay(hour: 6, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
          ColorScheme.light(primary: AppColors.kPrimaryColor),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      onSelected(picked);

      _updateWeeklyCard();
    }
  }

  void _showMultiSelectDialog() {
    List<String> tempSelected = List.from(selectedWorkouts);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(_isEditMode ? 'Edit Workouts' : 'Select Workouts'),
            content: SingleChildScrollView(
              child: Column(
                children: workoutOptions.map((workout) {
                  final isSelected = tempSelected.contains(workout);

                  return CheckboxListTile(
                    title: Text(workout),
                    value: isSelected,
                    activeColor: AppColors.kPrimaryColor,
                    onChanged: (bool? selected) {
                      setDialogState(() {
                        if (selected == true) {
                          tempSelected.add(workout);
                        } else {
                          tempSelected.remove(workout);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel")),
              TextButton(
                onPressed: () {
                  setState(() {
                    selectedWorkouts = tempSelected;
                  });

                  _updateWeeklyCard();

                  Navigator.pop(context);
                },
                child: Text("OK",
                    style: TextStyle(color: AppColors.kPrimaryColor)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _saveSchedule() async {

    if (!_formKey.currentState!.validate() ||
        selectedDay.isEmpty ||
        selectedWorkouts.isEmpty ||
        fromTime == null ||
        toTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final schedulerController = ProviderScope.containerOf(context)
        .read(DiProviders.schedulerControllerProvider.notifier);

    schedulerController.getTodayWorkOutSchedule(context);
    schedulerController.getWeeklyProgress(context);

    setState(() => _isLoading = true);

    try {
      final response = await _scheduleRepo.saveExerciseSchedule(
        userId: widget.userId,
        day: selectedDay,
        workouts: selectedWorkouts,
        fromTime: fromTime!.format(context),
        toTime: toTime!.format(context),
        scheduleId: _isEditMode ? _existingScheduleId : null,
      );

      if (response["status"] == "error") {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Already Booked"),
            content: Text(response["message"] ?? "This time slot is already booked."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );

        setState(() => _isLoading = false);
        return;
      }

      weeklySchedule ??= {
        "workouts": {},
        "fromTimes": {},
        "toTimes": {},
      };

      weeklySchedule!["workouts"][selectedDay] = selectedWorkouts;
      weeklySchedule!["fromTimes"][selectedDay] = fromTime!.format(context);
      weeklySchedule!["toTimes"][selectedDay] = toTime!.format(context);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        "weekly_schedule",
        jsonEncode(weeklySchedule),
      );


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response["message"] ?? "Schedule saved"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
          title: _isEditMode
              ? "Edit Exercise Schedule"
              : "Add Exercise Schedule"),
      body: SingleChildScrollView(
        padding: AppPaddings.backgroundPAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Edit your weekly exercise schedule",
              style:
              TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade900.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.indigo.shade900,
                  width: 1.5,
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Text("Day",
                        style: TextStyle(fontWeight: FontWeight.bold)),

                    CommonDropDownWidget(
                      items: [
                        "Monday",
                        "Tuesday",
                        "Wednesday",
                        "Thursday",
                        "Friday",
                        "Saturday",
                        "Sunday"
                      ],
                      hintText: "Select day",
                      primaryValue: selectedDay,
                      widgetIcon:
                      Icon(Icons.calendar_month_outlined),
                      onDropDwChanged: (val) {
                        setState(() {
                          selectedDay = val ?? '';
                        });

                        _updateWeeklyCard();
                      },
                    ),

                    const SizedBox(height: 20),

                    Text("Workouts",
                        style: TextStyle(fontWeight: FontWeight.bold)),

                    const SizedBox(height: 8),

                    InkWell(
                      onTap: _showMultiSelectDialog,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            vertical: 14, horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.kPrimaryColor
                                  .withOpacity(0.3)),
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.fitness_center,
                                color: AppColors.kPrimaryColor),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedWorkouts.isEmpty
                                    ? 'Select workout types'
                                    : selectedWorkouts
                                    .join(', '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text('From',
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight.bold)),
                              GestureDetector(
                                onTap: () => _pickTime(
                                  context,
                                      (t) {
                                    setState(
                                            () => fromTime = t);
                                    _updateWeeklyCard();
                                  },
                                  initial: fromTime,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors
                                            .kPrimaryColor
                                            .withOpacity(
                                            0.15)),
                                    borderRadius:
                                    BorderRadius.circular(
                                        10),
                                  ),
                                  child: Text(
                                    fromTime?.format(context) ??
                                        'Select time',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text('To',
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight.bold)),
                              GestureDetector(
                                onTap: () => _pickTime(
                                  context,
                                      (t) {
                                    setState(
                                            () => toTime = t);
                                    _updateWeeklyCard();
                                  },
                                  initial: toTime,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors
                                            .kPrimaryColor
                                            .withOpacity(
                                            0.15)),
                                    borderRadius:
                                    BorderRadius.circular(
                                        10),
                                  ),
                                  child: Text(
                                    toTime?.format(context) ??
                                        'Select time',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ButtonWidget(
                        text: _isEditMode
                            ? "Update Daily Schedule"
                            : "Add Daily Schedule",
                        isLoading: _isLoading,
                        borderRadius:
                        BorderRadius.circular(15),
                        backgroundColor: WidgetStatePropertyAll(
                            AppColors.kPrimaryColor),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                            color: AppColors.kWhite,
                            fontWeight:
                            FontWeight.bold),
                        onPressed: _saveSchedule,
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}