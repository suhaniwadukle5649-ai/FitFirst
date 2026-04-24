import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:orka_sports/presentation/view/home/data/repositories/home_repo_impl.dart';
import 'package:orka_sports/presentation/view/home/presentation/pages/all_coaches_screen.dart';
import 'package:orka_sports/presentation/view/home/presentation/pages/all_partners_screen.dart';
import 'package:orka_sports/presentation/view/home/presentation/pages/coach_details_screen.dart';
import 'package:orka_sports/presentation/view/home/presentation/pages/partner_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orka_sports/core/constants/app_colors.dart';
import 'package:orka_sports/core/constants/app_sizes_paddings.dart';
import 'package:orka_sports/presentation/view/home/presentation/controllers/home_controller.dart';
import 'package:orka_sports/presentation/view/home/domain/entities/home_entity.dart';
import 'package:orka_sports/presentation/view/home/data/models/get_allpartners_model.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../body/settings_screen/settings_screen.dart';

class CoachModel {
  final String id;
  final String userId;
  final String fullName;
  final String profilePhoto;
  final String dob;
  final String gender;
  final String country;
  final String state;
  final String city;
  final String address;
  final String contactNumber;
  final String altNumber;
  final String email;
  final String distance;
  final String? industry;
  final String? subIndustry;
  final String coachImageBase;
  final String? openToOnline;

  CoachModel({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.profilePhoto,
    required this.dob,
    required this.gender,
    required this.country,
    required this.state,
    required this.city,
    required this.address,
    required this.contactNumber,
    required this.altNumber,
    required this.email,
    required this.distance,
    this.industry,
    this.subIndustry,
    required this.coachImageBase,
    this.openToOnline,
  });

  factory CoachModel.fromJson(Map<String, dynamic> json) => CoachModel(
    id: json['id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    fullName: json['full_name']?.toString() ?? 'Unknown Coach',
    profilePhoto: json['profile_photo']?.toString() ?? '',
    dob: json['dob']?.toString() ?? '',
    gender: json['gender']?.toString() ?? '',
    country: json['country']?.toString() ?? '',
    state: json['state']?.toString() ?? '',
    city: json['city']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
    contactNumber: json['contact_number']?.toString() ?? '',
    altNumber: json['alt_number']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    distance: json['distance']?.toString() ?? '',
    industry: json['industry']?.toString(),
    subIndustry: json['sub_industry']?.toString(),
    coachImageBase: json['coach_image']?.toString() ?? '',
    openToOnline: json['open_to_online']?.toString(),
  );

  String get fullImageUrl {
    if (coachImageBase.isNotEmpty) return coachImageBase;
    if (profilePhoto.isNotEmpty && coachImageBase.isNotEmpty)
      return coachImageBase + profilePhoto;
    return '';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'full_name': fullName,
    'profile_photo': profilePhoto,
    'dob': dob,
    'gender': gender,
    'country': country,
    'state': state,
    'city': city,
    'address': address,
    'contact_number': contactNumber,
    'alt_number': altNumber,
    'email': email,
    'industry': industry,
    'sub_industry': subIndustry,
    'distance': distance,
    'coach_image': coachImageBase,
    'open_to_online': openToOnline,
  };
}

final homeControllerProvider =
StateNotifierProvider<HomeController, HomeEntity>(
        (ref) => HomeController());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String selectedLevel = 'All';
  bool isLoading = false;
  bool isCoachesLoading = false;
  bool isPartnersLoading = false;
  bool hasPartnersError = false;
  List<AllPartnersModel> _partnersList = [];
  late AnimationController fadeController;
  late AnimationController slideController;
  List<CoachModel> allCoaches = [];
  List<CoachModel> filteredCoaches = [];
  final List<String> levels = ['All', 'Gym', 'Yoga', 'Zumba'];

  static const Color _primaryBg   = Color(0xFFEAEEF8);
  static const Color _bg          = AppColors.background;
  static const Color _border      = AppColors.border;
  static const Color _dark        = AppColors.primary;       // 0xFF0A1950
  static const Color _darkNav     = AppColors.secondary;     // 0xFF1C2A4D
  static const Color _textSub     = AppColors.textSecondary; // 0xFF6B7280
  static const Color _accent      = AppColors.kYellowShade;  // 0xFFFFD971
  static const Color _pink        = Color(0xFFFF4080);
  static const Color _pinkBg      = Color(0xFFFFE9F1);
  static const Color _orange      = Color(0xFFFF6B00);
  static const Color _orangeBg    = Color(0xFFFFF0E0);

  double _sw = 390.0; 

  double _size(double base) => base * (_sw / 390.0);
  double _fontSize(double base) => base * (_sw / 390.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fadeController =
        AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    slideController =
        AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    fadeController.forward();
    slideController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadInitialData());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(homeControllerProvider);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) loadPartnersData();
      });
    }
  }

  Future<void> loadInitialData() async {
    try {
      await Future.wait([loadCoachesFromAPI(), loadPartnersData()]);
      updateUserLocation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to load data. Pull to refresh.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(label: 'Retry', onPressed: loadInitialData),
        ));
      }
    }
  }

  Future<void> loadPartnersData({int retryCount = 3}) async {
    if (!mounted) return;
    setState(() { isPartnersLoading = true; hasPartnersError = false; });
    int attempts = 0;
    bool success = false;
    while (attempts < retryCount && !success) {
      attempts++;
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString("userId");
        if (userId == null || userId.isEmpty) throw Exception('No user ID found');
        final homeRepoImpl = HomeRepoImpl();
        final result = await homeRepoImpl
            .getAllPartnersRepo(data: {"user_id": userId})
            .timeout(const Duration(seconds: 10));
        final partners = result.data ?? [];
        if (mounted) {
          setState(() {
            _partnersList = partners;
            isPartnersLoading = false;
            hasPartnersError = false;
          });
          ref.read(homeControllerProvider.notifier).getAllPartnersHome(context);
        }
        success = true;
      } catch (e) {
        if (attempts >= retryCount) {
          if (mounted) setState(() { isPartnersLoading = false; hasPartnersError = true; });
        } else {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  Future<void> updateUserLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString("userId");
      if (userId == null || userId.isEmpty) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        http.post(
          Uri.parse('https://fitfirst.online/Service/updateUserLocation'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'user_id': int.parse(userId),
            'latitude': position.latitude.toString(),
            'longitude': position.longitude.toString(),
          }),
        );
      }
    } catch (_) {}
  }

  Future<void> loadCoachesFromAPI({int retryCount = 3}) async {
    setState(() => isCoachesLoading = true);
    int attempts = 0;
    bool success = false;
    while (attempts < retryCount && !success) {
      attempts++;
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString("userId");
        if (userId == null || userId.isEmpty) break;
        final response = await http.post(
          Uri.parse('https://fitfirst.online/Service/getcoaches'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'userid': userId, 'type': selectedLevel.toLowerCase()},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'success') {
            final coachesJson = data['data'] as List<dynamic>? ?? [];
            if (mounted) {
              setState(() {
                allCoaches = coachesJson.map((j) => CoachModel.fromJson(j)).toList();
                filteredCoaches = allCoaches;
              });
            }
            success = true;
          }
        }
      } catch (_) {}
      if (!success && attempts < retryCount)
        await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) setState(() => isCoachesLoading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    fadeController.dispose();
    slideController.dispose();
    super.dispose();
  }

  Partner convertToPartner(AllPartnersModel apiPartner) => Partner(
    id: apiPartner.partnerId ?? '',
    name: apiPartner.partnerName ?? 'Unknown Partner',
    type: 'Partner',
    specialization: 'Fitness Center',
    rating: 4.5,
    distance: double.tryParse(apiPartner.distance ?? '0.0') ?? 0.0,
    imageUrl: apiPartner.partnerProfile ??
        'https://images.unsplash.com/photo-1571902943202-507ec2618e8f?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80',
    level: 'All Levels',
    price: 0,
    isOnline: true,
    address: 'Location available',
    hours: 'Open today',
    amenities: ['Fitness', 'Training'],
    productsAndServices: apiPartner.productsAndServices
        ?.map((p) => p.toJson())
        .toList() ??
        [],
  );

  Future<void> launchURL(String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $url'), backgroundColor: Colors.red));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error opening link'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> refreshData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([loadCoachesFromAPI(), loadPartnersData()]);
    } catch (_) {}
    finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _sw = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshData,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildHeader(),
              _buildCoachesSection(),
              _buildAdsBanner(),
              _buildPartnersSection(),
              SliverPadding(padding: EdgeInsets.only(bottom: _size(20))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        height: _size(210),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.secondary, Color(0xFF253A6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: -_size(50), right: -_size(50),
              child: Container(
                width: _size(200), height: _size(200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              top: -_size(30), left: -_size(30),
              child: Container(
                width: _size(150), height: _size(150),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(_size(20), _size(22), _size(20), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FitFirst',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: _fontSize(12),
                                    color: Colors.white60,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w500)),
                            SizedBox(height: _size(4)),
                            Text('FIND YOUR',
                                style: GoogleFonts.bebasNeue(
                                    fontSize: _fontSize(28), color: Colors.white, letterSpacing: 1)),
                            Text('PERFECT COACH',
                                style: GoogleFonts.bebasNeue(
                                    fontSize: _fontSize(28), color: _accent, letterSpacing: 1)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: _size(44),
                            height: _size(44),
                            padding: EdgeInsets.all(_size(6)),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(_size(14)),
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Image.asset(
                              'assets/images/Fit_First.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(height: _size(6)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: _size(10), vertical: _size(3)),
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(_size(20)),
                              border: Border.all(color: _accent.withOpacity(0.5)),
                            ),
                            child: Text('Fit First',
                                style: GoogleFonts.spaceGrotesk(
                                    color: _accent, fontSize: _fontSize(9), fontWeight: FontWeight.w700, letterSpacing: 1)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: _size(14)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: _size(16), vertical: _size(12)),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(_size(14)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: _size(20),
                          offset: Offset(0, _size(4)),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: _size(36),
                          width: _size(36),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(_size(10)),
                          ),
                          child: Icon(Icons.local_fire_department,
                              color: AppColors.primary, size: _size(20)),
                        ),

                        SizedBox(width: _size(12)),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Profile',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: _fontSize(13),
                                  fontWeight: FontWeight.w700,
                                  color: _dark,
                                ),
                              ),
                              Text(
                                'See your daily water intake and BMI details',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: _fontSize(11),
                                  color: _dark.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),

                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SettingsScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: _size(12), vertical: _size(6)),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(_size(8)),
                            ),
                            child: Text(
                              'Start',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: _fontSize(11),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachesSection() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: _size(20)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _size(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Coaches',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: _fontSize(18), fontWeight: FontWeight.w700, color: _dark)),
                  Text('Expert trainers near you',
                      style: GoogleFonts.spaceGrotesk(fontSize: _fontSize(11), color: _textSub)),
                ]),
                _outlinedButton(
                  label: 'View All',
                  color: AppColors.primary,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => AllCoachesScreen(coaches: allCoaches))),
                ),
              ],
            ),
          ),
          SizedBox(height: _size(14)),
          // Filter chips
          SizedBox(
            height: _size(38),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: _size(16)),
              itemCount: levels.length,
              separatorBuilder: (_, __) => SizedBox(width: _size(8)),
              itemBuilder: (context, index) {
                final level = levels[index];
                final isSelected = level == selectedLevel;
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedLevel = level);
                    loadCoachesFromAPI();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(horizontal: _size(18), vertical: _size(8)),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(_size(30)),
                      border: Border.all(
                          color: isSelected ? Colors.transparent : _border, width: 1),
                      boxShadow: isSelected
                          ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: _size(10), offset: Offset(0, _size(4)))]
                          : [],
                    ),
                    child: Text(level,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: _fontSize(12),
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : _dark.withOpacity(0.55))),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: _size(14)),
          // Coach cards
          SizedBox(
            height: _size(140),
            child: isCoachesLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                : filteredCoaches.isEmpty
                ? Center(
                child: Text('No coaches found',
                    style: GoogleFonts.spaceGrotesk(color: _textSub, fontSize: _fontSize(14))))
                : _buildCoachList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachList() {
    final displayCoaches = filteredCoaches.take(3).toList();
    final coachColors = [
      [AppColors.primary, AppColors.secondary],
      [_pink, const Color(0xFFFF6B9D)],
      [_orange, const Color(0xFFFF9A3C)],
    ];
    final coachBgColors = [_primaryBg, _pinkBg, _orangeBg];
    final coachLabelColors = [AppColors.primary, _pink, _orange];

    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - _size(32) - _size(10) * 2) / 3;
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _size(16)),
        physics: const BouncingScrollPhysics(),
        itemCount: displayCoaches.length,
        separatorBuilder: (_, __) => SizedBox(width: _size(10)),
        itemBuilder: (context, index) {
          final coach = displayCoaches[index];
          final gradColors = coachColors[index % coachColors.length];
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 600 + index * 100),
            tween: Tween(begin: 0, end: 1),
            builder: (context, val, _) => Transform.translate(
              offset: Offset(0, _size(20) * (1 - val)),
              child: Opacity(
                opacity: val,
                child: GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => CoachDetailsScreen(coach: coach.toMap()))),
                  child: Container(
                    width: cardWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(_size(20)),
                      border: Border.all(color: _border),
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.07), blurRadius: _size(16), offset: Offset(0, _size(4)))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: _size(58), height: _size(58),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(_size(18)),
                            gradient: LinearGradient(
                                colors: [gradColors[0], gradColors[1]],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                          ),
                          child: coach.coachImageBase.isNotEmpty
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(_size(18)),
                            child: CachedNetworkImage(
                              imageUrl: coach.coachImageBase,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Icon(Icons.person, color: Colors.white, size: _size(28)),
                              errorWidget: (_, __, ___) => Icon(Icons.person, color: Colors.white, size: _size(28)),
                            ),
                          )
                              : Icon(Icons.person, color: Colors.white, size: _size(28)),
                        ),
                        SizedBox(height: _size(8)),
                        Text(
                          coach.fullName.split(' ').first,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: _fontSize(13), fontWeight: FontWeight.w700, color: _dark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: _size(4)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: _size(9), vertical: _size(3)),
                          decoration: BoxDecoration(
                              color: coachBgColors[index % coachBgColors.length],
                              borderRadius: BorderRadius.circular(_size(10))),
                          child: Text(
                            (coach.industry ?? 'COACH').toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: _fontSize(9),
                                fontWeight: FontWeight.w700,
                                color: coachLabelColors[index % coachLabelColors.length],
                                letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildAdsBanner() {
    return SliverToBoxAdapter(
      child: Container(
        margin: EdgeInsets.fromLTRB(_size(16), _size(20), _size(16), 0),
        padding: EdgeInsets.all(_size(20)),
        decoration: BoxDecoration(
          color: _darkNav,
          borderRadius: BorderRadius.circular(_size(22)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -_size(70),
              left: -_size(40),
              child: Container(
                width: _size(100),
                height: _size(140),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
            ),
            Positioned(
              top: _size(30),
              right: -_size(30),
              child: Container(
                width: _size(60),
                height: _size(60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: _size(50),
                  height: _size(50),
                  decoration: BoxDecoration(
                    color: AppColors.kYellowShade.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(_size(16)),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.campaign_rounded,
                      color: AppColors.kYellowShade,
                      size: _size(26),
                    ),
                  ),
                ),
                SizedBox(width: _size(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partner with Fit First',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: _fontSize(15),
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: _size(3)),
                      Text(
                        'Grow your fitness business',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: _fontSize(11),
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: _size(10)),
                GestureDetector(
                  onTap: () => launchURL('https://fitfirst.online'),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: _size(8), vertical: _size(8)),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(_size(14)),
                      border: Border.all(color: _accent.withOpacity(0.5)),
                    ),
                    child: Text('Visit Website',
                        style: GoogleFonts.spaceGrotesk(
                            color: _accent, fontSize: _fontSize(10), fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnersSection() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: _size(24)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _size(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Eyebrow label
                  Row(children: [
                    Container(
                      width: _size(18),
                      height: _size(2),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(_size(2)),
                      ),
                    ),
                    SizedBox(width: _size(6)),
                    Text(
                      'NEARBY',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: _fontSize(10),
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ]),
                  SizedBox(height: _size(4)),
                  Text(
                    'Partners Near You',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: _fontSize(22),
                      fontWeight: FontWeight.w800,
                      color: _dark,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: _size(2)),
                  Text(
                    'Premium fitness locations',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: _fontSize(12),
                      color: _textSub,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ]),
                _outlinedButton(
                  label: 'View All',
                  color: AppColors.accent,
                  onTap: () {
                    final homeState = ref.read(homeControllerProvider);
                    final partnersData = homeState.getAllPartnersList?.data ?? [];
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllPartnersScreen(partners: partnersData),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: _size(16)),
          _buildPartnersContent(),
        ],
      ),
    );
  }

// ─── CONTENT STATES ──────────────────────────────────────────────────────────
  Widget _buildPartnersContent() {
    if (isPartnersLoading) {
      return SizedBox(
        height: _size(240),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: _size(42),
              height: _size(42),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: _size(16)),
            Text(
              'Searching for partners...',
              style: GoogleFonts.spaceGrotesk(
                color: _textSub,
                fontSize: _fontSize(13),
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),
      );
    }

    if (hasPartnersError) {
      return SizedBox(
        height: _size(240),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: EdgeInsets.all(_size(16)),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: _size(36),
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: _size(14)),
            Text(
              'Something went wrong',
              style: GoogleFonts.spaceGrotesk(
                color: _dark,
                fontSize: _fontSize(15),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: _size(4)),
            Text(
              'Could not load partners',
              style: GoogleFonts.spaceGrotesk(
                color: _textSub,
                fontSize: _fontSize(12),
              ),
            ),
            SizedBox(height: _size(16)),
            GestureDetector(
              onTap: loadPartnersData,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _size(24),
                  vertical: _size(10),
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(_size(30)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: _size(12),
                      offset: Offset(0, _size(4)),
                    )
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: _size(15)),
                  SizedBox(width: _size(6)),
                  Text(
                    'Retry',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: _fontSize(13),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    if (_partnersList.isEmpty) {
      return SizedBox(
        height: _size(240),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: EdgeInsets.all(_size(18)),
              decoration: BoxDecoration(
                color: _primaryBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: _size(36),
                color: AppColors.primary.withOpacity(0.5),
              ),
            ),
            SizedBox(height: _size(14)),
            Text(
              'No partners found near you',
              style: GoogleFonts.spaceGrotesk(
                color: _dark,
                fontSize: _fontSize(15),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: _size(4)),
            Text(
              'Try refreshing or expanding your area',
              style: GoogleFonts.spaceGrotesk(
                color: _textSub,
                fontSize: _fontSize(12),
              ),
            ),
            SizedBox(height: _size(16)),
            GestureDetector(
              onTap: loadPartnersData,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _size(20),
                  vertical: _size(9),
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(_size(30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded,
                      color: AppColors.primary, size: _size(15)),
                  SizedBox(width: _size(6)),
                  Text(
                    'Refresh',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.primary,
                      fontSize: _fontSize(13),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    final partners = _partnersList.map(convertToPartner).toList();
    return SizedBox(
      height: _size(250),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          left: _size(16),
          right: _size(4),
          bottom: _size(4),
          top: _size(2),
        ),
        itemCount: partners.length,
        itemBuilder: (context, index) => Container(
          width: _size(300),
          margin: EdgeInsets.only(right: _size(14)),
          child: _buildPartnerCard(partners[index]),
        ),
      ),
    );
  }

  Widget _buildPartnerCard(Partner partner) {
    return GestureDetector(
      onTap: () {
        final matchingPartner = _partnersList.firstWhere(
              (p) => p.partnerId == partner.id,
          orElse: () => AllPartnersModel(),
        );
        final data = {
          'partnerID': matchingPartner.partnerId ?? partner.id,
          'partnerName': matchingPartner.partnerName ?? partner.name,
          'partnerProfile': matchingPartner.partnerProfile ?? partner.imageUrl,
          'distance': matchingPartner.distance ?? partner.distance.toString(),
          'partnerLat': matchingPartner.partnerLat ?? '0.0',
          'partnerLong': matchingPartner.partnerLong ?? '0.0',
          'partner_image': matchingPartner.partnerImage,
          'about': matchingPartner.about,
          'mobile': matchingPartner.mobile,
          'start_time_monday': matchingPartner.startTimeMonday,
          'end_time_monday': matchingPartner.endTimeMonday,
          'start_time_tuesday': matchingPartner.startTimeTuesday,
          'end_time_tuesday': matchingPartner.endTimeTuesday,
          'start_time_wednesday': matchingPartner.startTimeWednesday,
          'end_time_wednesday': matchingPartner.endTimeWednesday,
          'start_time_thursday': matchingPartner.startTimeThursday,
          'end_time_thursday': matchingPartner.endTimeThursday,
          'start_time_friday': matchingPartner.startTimeFriday,
          'end_time_friday': matchingPartner.endTimeFriday,
          'start_time_saturday': matchingPartner.startTimeSaturday,
          'end_time_saturday': matchingPartner.endTimeSaturday,
          'start_time_sunday': matchingPartner.startTimeSunday,
          'end_time_sunday': matchingPartner.endTimeSunday,
          'product_subcategories': matchingPartner.productSubcategories,
          'products_and_services': matchingPartner.productsAndServices
              ?.map((p) => p.toJson())
              .toList() ??
              [],
        };

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PartnerDetailsScreen(partner: data),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_size(22)),
          border: Border.all(color: _border.withOpacity(0.9), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
              blurRadius: _size(20),
              offset: Offset(0, _size(6)),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: _size(4),
              offset: Offset(0, _size(1)),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_size(22)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: _size(160),
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: partner.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: _primaryBg,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: _primaryBg,
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: _textSub,
                            size: _size(32),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: _size(45),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: _size(11),
                    left: _size(11),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: _size(10),
                        vertical: _size(4),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954),
                        borderRadius: BorderRadius.circular(_size(30)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1DB954).withOpacity(0.4),
                            blurRadius: _size(8),
                            offset: Offset(0, _size(2)),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: _size(5),
                            height: _size(5),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: _size(4)),
                          Text(
                            'OPEN',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: _fontSize(9),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: _size(11),
                    right: _size(11),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: _size(10),
                        vertical: _size(4),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(_size(30)),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            color: Colors.white,
                            size: _size(10),
                          ),
                          SizedBox(width: _size(3)),
                          Text(
                            _getDistanceLabel(partner),
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: _fontSize(10),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: EdgeInsets.all(_size(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.name,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: _fontSize(15),
                              fontWeight: FontWeight.w800,
                              color: _dark,
                              height: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: _size(2)),
                          _buildTimingRow(partner),
                          SizedBox(height: _size(4)),
                          Row(
                            children: [
                              _miniTag('Fitness', _primaryBg, AppColors.primary),
                              SizedBox(width: _size(4)),
                              _miniTag('Training', _primaryBg, AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: _size(8)),
                    GestureDetector(
                      onTap: () => openGoogleMaps(partner),
                      child: Container(
                        width: _size(52),
                        padding: EdgeInsets.symmetric(vertical: _size(8)),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.accent, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(_size(14)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.30),
                              blurRadius: _size(12),
                              offset: Offset(0, _size(4)),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.near_me_rounded,
                              color: Colors.white,
                              size: _size(16),
                            ),
                            SizedBox(height: _size(2)),
                            Text(
                              'Go',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: _fontSize(9),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDistanceLabel(Partner partner) {
    final match = _partnersList.firstWhere(
          (p) => p.partnerId == partner.id,
      orElse: () => AllPartnersModel(),
    );
    final d = double.tryParse(match.distance ?? '0.0') ?? 0.0;
    return '${d.toStringAsFixed(1)} km';
  }

  Widget _buildTimingRow(Partner partner) {
    final match = _partnersList.firstWhere(
          (p) => p.partnerId == partner.id,
      orElse: () => AllPartnersModel(),
    );
    final dayNames = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday',
    ];
    final todayName = dayNames[DateTime.now().weekday - 1];
    final timing = getTodayTiming(match.toJson(), todayName);

    return Row(children: [
      // Animated dot
      Container(
        width: _size(6),
        height: _size(6),
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1DB954).withOpacity(0.5),
              blurRadius: _size(4),
            )
          ],
        ),
      ),
      SizedBox(width: _size(6)),
      Expanded(
        child: Text(
          timing.isNotEmpty ? 'Open · $timing' : 'Open Today',
          style: GoogleFonts.spaceGrotesk(
            color: _textSub,
            fontSize: _fontSize(11),
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  Widget _miniTag(String label, Color bg, Color fg) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _size(9),
        vertical: _size(3),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_size(8)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: _fontSize(9),
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _outlinedButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _size(16),
          vertical: _size(7),
        ),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(_size(30)),
          color: color.withOpacity(0.06),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: _fontSize(11),
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(width: _size(4)),
            Icon(Icons.arrow_forward_rounded, size: _size(12), color: color),
          ],
        ),
      ),
    );
  }

  Future<void> openGoogleMaps(Partner partner) async {
    try {
      final match = _partnersList.firstWhere(
            (p) => p.partnerId == partner.id,
        orElse: () => AllPartnersModel(),
      );
      final lat = double.tryParse(match.partnerLat ?? '0.0') ?? 0.0;
      final lng = double.tryParse(match.partnerLong ?? '0.0') ?? 0.0;
      if (lat == 0.0 && lng == 0.0) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location not available'),
            backgroundColor: Colors.orange,
          ));
        return;
      }
      final url =
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        final fallback = 'https://maps.google.com/?q=$lat,$lng';
        if (await canLaunchUrl(Uri.parse(fallback)))
          await launchUrl(Uri.parse(fallback),
              mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to open Google Maps'),
          backgroundColor: Colors.red,
        ));
    }
  }

  String getTodayTiming(Map<String, dynamic> partner, String dayName) {
    final start = partner['start_time_$dayName']?.toString() ?? '';
    final end = partner['end_time_$dayName']?.toString() ?? '';
    return (start.isNotEmpty && end.isNotEmpty) ? '$start - $end' : '';
  }
}

class Partner {
  final String id;
  final String name;
  final String type;
  final String specialization;
  final double rating;
  final double distance;
  final String imageUrl;
  final String level;
  final int price;
  final bool isOnline;
  final String? address;
  final bool? isNew;
  final String? hours;
  final String? experience;
  final int? sessions;
  final List<String>? amenities;
  final List<Map<String, dynamic>>? productsAndServices;

  Partner({
    required this.id,
    required this.name,
    required this.type,
    required this.specialization,
    required this.rating,
    required this.distance,
    required this.imageUrl,
    required this.level,
    required this.price,
    required this.isOnline,
    this.address,
    this.isNew,
    this.hours,
    this.experience,
    this.sessions,
    this.amenities,
    this.productsAndServices,
  });
}
