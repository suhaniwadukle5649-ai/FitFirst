import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_advanced_drawer/flutter_advanced_drawer.dart';
import 'package:orka_sports/core/constants/app_colors.dart';
import 'package:orka_sports/core/utils/custom_smooth_navigation.dart';
import 'package:orka_sports/presentation/blocs/activity_list/activity_list_event.dart';
import 'package:orka_sports/presentation/blocs/activity_list/activity_list_state.dart';
import 'package:orka_sports/presentation/blocs/profile/profile_bloc.dart';
import 'package:orka_sports/presentation/blocs/activity_list/activity_list_bloc.dart';
import 'package:orka_sports/presentation/view/body/activity_screen/activity_screen.dart';
import 'package:orka_sports/presentation/view/body/settings_screen/settings_screen.dart';
import 'package:orka_sports/presentation/view/body/settings_screen/user_profile/slide_profile_view.dart';
import 'package:orka_sports/presentation/view/body_iq/presentation/pages/bodyiq_dashboard/bodyiq_dashboard.dart';
import 'package:orka_sports/presentation/view/gym/presentation/pages/dashborad/gym_dashboad.dart';
import 'package:orka_sports/presentation/view/home/presentation/pages/home_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {

  final AdvancedDrawerController _advancedDrawerController =
  AdvancedDrawerController();

  void _handleMenuButtonPressed() {
    _advancedDrawerController.showDrawer();
  }

  static const _screens = [
    HomeScreen(),
    ActivityScreen(),
    GymDashboardScreen(),
    BodyiqDashboardScreen(),
  ];

  static const _titles = ['Home', 'Activity', 'Gym', 'Body IQ'];

  static const _icons = [
    Icons.home_sharp,
    Icons.directions_walk,
    Icons.fitness_center_rounded,
    Icons.self_improvement,
  ];

  late double _displayWidth;
  late double _navBarHeight;
  late double _verticalMargin;
  bool _isInitialLoading = false;
  bool _hasLoadedData = false;

  @override
  void initState() {
    super.initState();
    _loadAllDataInParallel();
  }

  Future<void> _loadAllDataInParallel() async {
    if (_hasLoadedData) return;
    _hasLoadedData = true;

    setState(() => _isInitialLoading = true);

    try {
      debugPrint("🚀 Starting parallel data loading...");
      final startTime = DateTime.now();

      await Future.wait([
        _loadProfileIfNeeded(),
        _loadActivitiesIfNeeded(),
        _loadBodyIQDataIfNeeded(),
      ]);

      final duration = DateTime.now().difference(startTime);
      debugPrint(
          "⚡ All parallel loading completed in ${duration.inMilliseconds}ms");
    } catch (e) {
      debugPrint("❌ Error in parallel loading: $e");
    } finally {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  Future<void> _loadBodyIQDataIfNeeded() async {
    try {
      debugPrint("🧠 BodyIQ loading would start here");
    } catch (e) {
      debugPrint("❌ Error loading BodyIQ data: $e");
    }
  }

  Future<void> _loadProfileIfNeeded() async {
    try {
      if (context.read<ProfileBloc>().state is! ProfileLoaded) {
        context.read<ProfileBloc>().add(LoadProfile());
      }
    } catch (e) {
      debugPrint("❌ Error loading profile: $e");
    }
  }

  Future<void> _loadActivitiesIfNeeded() async {
    try {
      if (context.read<ActivityListBloc>().state is! ActivityListLoaded) {
        context.read<ActivityListBloc>().add(LoadActivityList());
      }
    } catch (e) {
      debugPrint("❌ Error loading activities: $e");
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _displayWidth = MediaQuery.of(context).size.width;
    _navBarHeight = _displayWidth * 0.16;
    _verticalMargin = _displayWidth * 0.08;
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
                SizedBox(height: 20),
                Text(
                  'Loading app data...',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please wait',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return BlocSelector<ProfileBloc, ProfileState, int>(
      selector: (state) =>
      (state is ProfileLoaded) ? state.currentIndex : 0,
      builder: (context, currentIndex) {

        return AdvancedDrawer(
          controller: _advancedDrawerController,
          backdropColor: AppColors.primary,
          animationCurve: Curves.easeInOut,
          animationDuration: const Duration(milliseconds: 300),
          childDecoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
          ),
          drawer: const SideProfileView(),
          child: Scaffold(
            appBar: _buildAppBar(currentIndex),
            body: SafeArea(
              child: IndexedStack(
                index: currentIndex,
                children: _screens,
              ),
            ),
            bottomNavigationBar: _BottomNavBar(
              currentIndex: currentIndex,
              width: _displayWidth,
              navBarHeight: _navBarHeight,
              verticalMargin: _verticalMargin,
              onTap: (i) {
                context.read<ProfileBloc>().add(ChangeTabIndex(i));
                HapticFeedback.lightImpact();
              },
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(int currentIndex) {
    return AppBar(
      backgroundColor: AppColors.background,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: _handleMenuButtonPressed,
      ),
      title: Text(
        _titles[currentIndex],
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
      centerTitle: true,
      actions: [
        _ProfileAvatar(displayWidth: _displayWidth),
        const SizedBox(width: 15),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.width,
    required this.navBarHeight,
    required this.verticalMargin,
    required this.onTap,
  });

  final int currentIndex;
  final double width, navBarHeight, verticalMargin;
  final ValueChanged<int> onTap;

  static const _titles = _MainScreenState._titles;
  static const _icons = _MainScreenState._icons;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: width,
        height: navBarHeight * 1,
        margin: EdgeInsets.only(
          left: width * 0.04,
          right: width * 0.04,
          bottom: verticalMargin,
        ),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          tween: Tween<double>(begin: 0, end: currentIndex.toDouble()),
          builder: (context, animValue, child) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(width * 0.92, navBarHeight * 1.3),
                  painter: BNBCustomPainter(
                    animatedIndex: animValue,
                    itemCount: _titles.length,
                  ),
                ),
                Row(
                  children: List.generate(_titles.length, (i) {
                    return _NavItem(
                      icon: _icons[i],
                      selected: i == currentIndex,
                      width: width,
                      navBarHeight: navBarHeight,
                      onTap: () => onTap(i),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selected,
    required this.width,
    required this.navBarHeight,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final double width;
  final double navBarHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          transform: Matrix4.translationValues(
            0,
            selected ? -navBarHeight * 0.40 : 0,
            0,
          ),
          child: Container(
            width: width * 0.16,
            height: width * 0.14,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white
                  : Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: selected
                  ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                )
              ]
                  : [],
            ),
            child: Icon(
              icon,
              size: selected ? width * 0.075 : width * 0.065,
              color: selected
                  ? AppColors.primary
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class BNBCustomPainter extends CustomPainter {
  final double animatedIndex;
  final int itemCount;

  BNBCustomPainter({required this.animatedIndex, required this.itemCount});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    double itemWidth = size.width / itemCount;
    double centerX = (animatedIndex * itemWidth) + (itemWidth / 2);

    Path path = Path();
    double radius = 35;

    path.moveTo(0, 0);
    path.lineTo(radius, 0);
    path.lineTo(centerX - 55, 0);
    path.cubicTo(centerX - 35, 0, centerX - 40, 45, centerX, 45);
    path.cubicTo(centerX + 40, 45, centerX + 35, 0, centerX + 55, 0);

    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(size.width, size.height,
        size.width - radius, size.height);
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.close();

    canvas.drawShadow(path, Colors.black.withAlpha(100), 15, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BNBCustomPainter oldDelegate) =>
      oldDelegate.animatedIndex != animatedIndex;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.displayWidth});

  final double displayWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => CustomSmoothNavigator.push(context, SettingsScreen()),
      child: Padding(
        padding: EdgeInsets.only(
            left: displayWidth * 0.04, top: displayWidth * 0.02),
        child: BlocBuilder<ProfileBloc, ProfileState>(
          buildWhen: (prev, curr) => prev != curr,
          builder: (context, state) {
            final imageUrl = (state is ProfileLoaded &&
                state.profile.profileImage != null &&
                state.profile.profileImage!.isNotEmpty)
                ? state.profile.profileImage
                : null;

            return CircleAvatar(
              backgroundColor: Colors.white,
              radius: 20,
              child: ClipOval(
                child: imageUrl == null
                    ? Icon(Icons.person,
                    size: displayWidth * 0.08,
                    color: AppColors.primary)
                    : CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: displayWidth * 0.08,
                  height: displayWidth * 0.08,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Icon(Icons.person,
                      size: displayWidth * 0.08,
                      color: AppColors.primary),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}