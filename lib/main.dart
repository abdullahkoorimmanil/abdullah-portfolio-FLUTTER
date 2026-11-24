import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'site_metadata_stub.dart'
    if (dart.library.js_interop) 'site_metadata_web.dart' as site_metadata;

const _ink = Color(0xFF090B10);
const _panel = Color(0xFF11151D);
const _muted = Color(0xFF929BAA);
const _lime = Color(0xFFC8FF65);
const _cyan = Color(0xFF65E8FF);
const _violet = Color(0xFF9E7BFF);
const _defaultSkills = <String>[
  'Art direction',
  'Flutter',
  'Motion design',
  'Interaction',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final cloudEnabled =
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  if (cloudEnabled) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
  final store = PortfolioStore(cloudEnabled: cloudEnabled);
  await store.load();
  site_metadata.updateSiteMetadata(store.data.siteTitle, store.data.appIcon);
  runApp(AntigravityPortfolio(store: store));
}

class PortfolioStore extends ChangeNotifier {
  PortfolioStore({required this.cloudEnabled});

  static const _storageKey = 'antigravity.portfolio.v1';
  static const _bucket = 'portfolio-media';
  static const _rowId = 'main';
  final bool cloudEnabled;
  PortfolioData data = PortfolioData.initial();

  SupabaseClient? get _client => cloudEnabled ? Supabase.instance.client : null;
  bool get isAdminSignedIn => _client?.auth.currentUser != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      try {
        data = PortfolioData.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } catch (_) {
        data = PortfolioData.initial();
      }
    }

    if (cloudEnabled) {
      try {
        final record = await _client!
            .from('portfolio_content')
            .select('content')
            .eq('id', _rowId)
            .maybeSingle();
        final content = record?['content'];
        if (content is Map<String, dynamic>) {
          data = PortfolioData.fromJson(content).copyWith(
            adminPin: data.adminPin,
          );
          await prefs.setString(_storageKey, jsonEncode(data.toJson()));
        }
      } catch (_) {
        // Keep the saved browser copy available while the cloud is offline or
        // before the database has been configured.
      }
    }
  }

  Future<void> save(PortfolioData next) async {
    var saved = next;
    if (cloudEnabled) {
      if (!isAdminSignedIn) {
        throw StateError('Sign in to your admin account before saving.');
      }
      saved = await _uploadImages(next);
      await _client!.from('portfolio_content').upsert(
        {'id': _rowId, 'content': saved.toCloudJson()},
        onConflict: 'id',
      );
    }
    data = saved;
    site_metadata.updateSiteMetadata(data.siteTitle, data.appIcon);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(data.toJson()));
    notifyListeners();
  }

  Future<PortfolioData> _uploadImages(PortfolioData source) async {
    final avatar = await _uploadImage(source.avatar, 'profile/avatar');
    final brandImage = await _uploadImage(source.brandImage, 'profile/brand');
    final appIcon = await _uploadImage(source.appIcon, 'profile/app-icon');
    final heroImage = await _uploadImage(source.heroImage, 'profile/home');
    final projects = <PortfolioProject>[];
    for (var index = 0; index < source.projects.length; index++) {
      final project = source.projects[index];
      final slug = project.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final image = await _uploadImage(
        project.image,
        'projects/$index-${slug.isEmpty ? 'work' : slug}',
      );
      projects.add(
        PortfolioProject(
          title: project.title,
          category: project.category,
          description: project.description,
          image: image,
          url: project.url,
          tag: project.tag,
        ),
      );
    }
    return source.copyWith(
      avatar: avatar,
      brandImage: brandImage,
      appIcon: appIcon,
      heroImage: heroImage,
      projects: projects,
    );
  }

  Future<String> _uploadImage(String value, String pathWithoutExtension) async {
    if (!value.startsWith('data:')) return value;
    final comma = value.indexOf(',');
    if (comma < 0) throw const FormatException('Invalid selected image.');
    final mime = value.substring(5, value.indexOf(';'));
    final extension = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$pathWithoutExtension.$extension';
    await _client!.storage.from(_bucket).uploadBinary(
          path,
          base64Decode(value.substring(comma + 1)),
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    final publicUrl = _client!.storage.from(_bucket).getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> signIn(String email, String password) async {
    await _client!.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}

class PortfolioData {
  const PortfolioData({
    required this.name,
    required this.siteTitle,
    required this.role,
    required this.headline,
    required this.summary,
    required this.about,
    required this.location,
    required this.email,
    required this.phone,
    required this.avatar,
    required this.brandImage,
    required this.appIcon,
    required this.heroImage,
    required this.adminPin,
    required this.skills,
    required this.projects,
    required this.links,
  });

  final String name;
  final String siteTitle;
  final String role;
  final String headline;
  final String summary;
  final String about;
  final String location;
  final String email;
  final String phone;
  final String avatar;
  final String brandImage;
  final String appIcon;
  final String heroImage;
  final String adminPin;
  final List<String> skills;
  final List<PortfolioProject> projects;
  final List<PortfolioLink> links;

  factory PortfolioData.initial() => PortfolioData(
        name: 'ABDULLAH KP',
        siteTitle: 'Abdullah Portfolio',
        role: 'softwer developer  |flutter developer | vibe coder',
        headline: 'I make digital\nfeel different.',
        summary:
            'Independent creative building brave brands, expressive websites, and motion that makes people pause.',
        about:
            'I blend design and code to make digital experiences feel intuitive, full of character, and a little unexpected. From the first sketch to the final transition, every detail has a reason to be there.',
        location: 'Based anywhere · Available worldwide',
        email: 'hello@alexmorgan.design',
        phone: '+1 415 555 0182',
        avatar: '',
        brandImage: '',
        appIcon: '',
        heroImage: '',
        adminPin: '0003',
        skills: _defaultSkills,
        projects: const [
          PortfolioProject(
            title: 'Form / Function',
            category: 'Digital experience · 2025',
            description:
                'An editorial storefront that turns responsible design into a tactile, curious shopping experience.',
            image: '',
            url: 'https://example.com',
            tag: 'E-COMMERCE',
          ),
          PortfolioProject(
            title: 'New Ritual',
            category: 'Brand world · 2025',
            description:
                'A fresh visual identity and launch site for a new generation of thoughtful daily rituals.',
            image: '',
            url: 'https://example.com',
            tag: 'BRANDING',
          ),
          PortfolioProject(
            title: 'Good Outside',
            category: 'Campaign · 2024',
            description:
                'A bright, playful campaign inviting people to take the long way home.',
            image: '',
            url: 'https://example.com',
            tag: 'CAMPAIGN',
          ),
        ],
        links: const [
          PortfolioLink(label: 'Instagram', url: 'https://instagram.com/'),
          PortfolioLink(label: 'LinkedIn', url: 'https://linkedin.com/'),
          PortfolioLink(label: 'Email', url: 'mailto:hello@alexmorgan.design'),
          PortfolioLink(label: 'Phone', url: 'tel:+14155550182'),
        ],
      );

  factory PortfolioData.fromJson(Map<String, dynamic> json) => PortfolioData(
        name: json['name'] as String? ?? 'Alex Morgan',
        siteTitle: json['siteTitle'] as String? ?? 'Abdullah Portfolio',
        role: json['role'] as String? ?? '',
        headline: json['headline'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        about: json['about'] as String? ?? '',
        location: json['location'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        brandImage: json['brandImage'] as String? ?? '',
        appIcon: json['appIcon'] as String? ?? '',
        heroImage: json['heroImage'] as String? ?? '',
        adminPin: json['adminPin'] as String? ?? '2468',
        skills: (json['skills'] as List<dynamic>? ?? _defaultSkills)
            .map((e) => e.toString())
            .toList(),
        projects: (json['projects'] as List<dynamic>? ?? const [])
            .map((e) => PortfolioProject.fromJson(e as Map<String, dynamic>))
            .toList(),
        links: (json['links'] as List<dynamic>? ?? const [])
            .map((e) => PortfolioLink.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'siteTitle': siteTitle,
        'role': role,
        'headline': headline,
        'summary': summary,
        'about': about,
        'location': location,
        'email': email,
        'phone': phone,
        'avatar': avatar,
        'brandImage': brandImage,
        'appIcon': appIcon,
        'heroImage': heroImage,
        'adminPin': adminPin,
        'skills': skills,
        'projects': projects.map((e) => e.toJson()).toList(),
        'links': links.map((e) => e.toJson()).toList(),
      };

  Map<String, dynamic> toCloudJson() => {
        'name': name,
        'siteTitle': siteTitle,
        'role': role,
        'headline': headline,
        'summary': summary,
        'about': about,
        'location': location,
        'email': email,
        'phone': phone,
        'avatar': avatar,
        'brandImage': brandImage,
        'appIcon': appIcon,
        'heroImage': heroImage,
        'skills': skills,
        'projects': projects.map((e) => e.toJson()).toList(),
        'links': links.map((e) => e.toJson()).toList(),
      };

  PortfolioData copyWith({
    String? name,
    String? siteTitle,
    String? role,
    String? headline,
    String? summary,
    String? about,
    String? location,
    String? email,
    String? phone,
    String? avatar,
    String? brandImage,
    String? appIcon,
    String? heroImage,
    String? adminPin,
    List<String>? skills,
    List<PortfolioProject>? projects,
    List<PortfolioLink>? links,
  }) =>
      PortfolioData(
        name: name ?? this.name,
        siteTitle: siteTitle ?? this.siteTitle,
        role: role ?? this.role,
        headline: headline ?? this.headline,
        summary: summary ?? this.summary,
        about: about ?? this.about,
        location: location ?? this.location,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        avatar: avatar ?? this.avatar,
        brandImage: brandImage ?? this.brandImage,
        appIcon: appIcon ?? this.appIcon,
        heroImage: heroImage ?? this.heroImage,
        adminPin: adminPin ?? this.adminPin,
        skills: skills ?? this.skills,
        projects: projects ?? this.projects,
        links: links ?? this.links,
      );
}

class PortfolioProject {
  const PortfolioProject({
    required this.title,
    required this.category,
    required this.description,
    required this.image,
    required this.url,
    required this.tag,
  });

  final String title;
  final String category;
  final String description;
  final String image;
  final String url;
  final String tag;

  factory PortfolioProject.fromJson(Map<String, dynamic> json) =>
      PortfolioProject(
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? '',
        description: json['description'] as String? ?? '',
        image: json['image'] as String? ?? '',
        url: json['url'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'description': description,
        'image': image,
        'url': url,
        'tag': tag,
      };
}

class PortfolioLink {
  const PortfolioLink({required this.label, required this.url});
  final String label;
  final String url;
  factory PortfolioLink.fromJson(Map<String, dynamic> json) => PortfolioLink(
        label: json['label'] as String? ?? 'Link',
        url: json['url'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class AntigravityPortfolio extends StatelessWidget {
  const AntigravityPortfolio({super.key, required this.store});
  final PortfolioStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Portfolio',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _ink,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _lime,
            brightness: Brightness.dark,
          ),
          fontFamily: 'Arial',
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: .04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _lime),
            ),
            labelStyle: const TextStyle(color: _muted),
          ),
        ),
        home: PortfolioHome(store: store),
      );
}

class PortfolioHome extends StatefulWidget {
  const PortfolioHome({super.key, required this.store});
  final PortfolioStore store;
  @override
  State<PortfolioHome> createState() => _PortfolioHomeState();
}

class _PortfolioHomeState extends State<PortfolioHome> {
  final _pageController = PageController();
  int _selectedPage = 0;

  void _selectPage(int index) {
    if (index == _selectedPage) return;
    setState(() => _selectedPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openAdmin() async {
    final allowed = widget.store.isAdminSignedIn
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (_) => widget.store.cloudEnabled
                ? _AdminSignInDialog(store: widget.store)
                : _AdminPinDialog(adminPin: widget.store.data.adminPin),
          );
    if (allowed == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AdminDashboard(store: widget.store)),
      );
    } else if (allowed == false && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            widget.store.cloudEnabled
                ? 'Admin sign-in was not completed.'
                : 'That PIN did not match.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final data = widget.store.data;
          return Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(child: MotionBackdrop()),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, viewport) {
                      final compact = viewport.maxWidth < 760;
                      final dense = viewport.maxHeight < 420;
                      return Column(
                        children: [
                          _SiteNav(
                            data: data,
                            compact: compact,
                            dense: dense,
                            onAdmin: _openAdmin,
                          ),
                          Expanded(
                            child: PageView(
                              controller: _pageController,
                              physics: const PageScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              dragStartBehavior: DragStartBehavior.down,
                              onPageChanged: (index) =>
                                  setState(() => _selectedPage = index),
                              children: [
                                _SectionViewport(
                                  child: _HeroSection(
                                    data: data,
                                    compact: compact,
                                    onWork: () => _selectPage(2),
                                    onContact: () => _selectPage(3),
                                  ),
                                ),
                                _SectionViewport(
                                  child: _AboutSection(
                                    data: data,
                                    compact: compact,
                                  ),
                                ),
                                _SectionViewport(
                                  child: _WorkSection(data: data),
                                ),
                                _SectionViewport(
                                  child: Column(
                                    children: [
                                      _ContactSection(data: data),
                                      _Footer(
                                        data: data,
                                        onAdmin: _openAdmin,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _BottomDock(
                            selectedIndex: _selectedPage,
                            compact: compact,
                            dense: dense,
                            onSelect: _selectPage,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _SectionViewport extends StatelessWidget {
  const _SectionViewport({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: child,
      );
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.selectedIndex,
    required this.compact,
    required this.dense,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool compact;
  final bool dense;
  final ValueChanged<int> onSelect;

  static const _tabs = [
    _DockTab('Home', Icons.home_rounded),
    _DockTab('About', Icons.person_outline_rounded),
    _DockTab('Projects', Icons.grid_view_rounded),
    _DockTab('Contact', Icons.mail_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          dense ? 6 : (compact ? 14 : 24),
          dense ? 2 : 8,
          dense ? 6 : (compact ? 14 : 24),
          dense ? 4 : (compact ? 9 : 18),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              height: dense ? 48 : (compact ? 68 : 74),
              padding: EdgeInsets.all(dense ? 3 : 5),
              decoration: BoxDecoration(
                color: const Color(0xE910131A),
                borderRadius: BorderRadius.circular(dense ? 24 : 32),
                border: Border.all(color: Colors.white.withValues(alpha: .13)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .4),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: _lime.withValues(alpha: .045),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: _BottomDockItem(
                        tab: _tabs[i],
                        selected: i == selectedIndex,
                        dense: dense,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DockTab {
  const _DockTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _BottomDockItem extends StatefulWidget {
  const _BottomDockItem({
    required this.tab,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final _DockTab tab;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  State<_BottomDockItem> createState() => _BottomDockItemState();
}

class _BottomDockItemState extends State<_BottomDockItem> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  Widget build(BuildContext context) => Tooltip(
        message: widget.tab.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHover: _setHovered,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: BorderRadius.circular(26),
              child: AnimatedScale(
                scale: _pressed ? .93 : (_hovered ? 1.065 : 1),
                duration: Duration(milliseconds: _pressed ? 100 : 200),
                curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: EdgeInsets.symmetric(vertical: widget.dense ? 4 : 7),
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? _lime.withValues(alpha: .16)
                        : (_hovered
                            ? _cyan.withValues(alpha: .09)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: widget.selected
                          ? _lime.withValues(alpha: .30)
                          : (_hovered
                              ? _cyan.withValues(alpha: .28)
                              : Colors.transparent),
                    ),
                    boxShadow: _hovered || widget.selected
                        ? [
                            BoxShadow(
                              color: (widget.selected ? _lime : _cyan)
                                  .withValues(alpha: _hovered ? .18 : .09),
                              blurRadius: _hovered ? 20 : 12,
                              spreadRadius: _hovered ? 1 : 0,
                            ),
                          ]
                        : const [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: widget.selected ? 1.12 : (_hovered ? 1.14 : 1),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          widget.tab.icon,
                          size: widget.dense ? 16 : 19,
                          color: widget.selected
                              ? _lime
                              : (_hovered ? _cyan : const Color(0xFF929BAA)),
                        ),
                      ),
                      SizedBox(height: widget.dense ? 1 : 3),
                      Text(
                        widget.tab.label,
                        maxLines: 1,
                        style: TextStyle(
                          color: widget.selected
                              ? _lime
                              : (_hovered ? _cyan : const Color(0xFF929BAA)),
                          fontSize: widget.dense ? 8 : 10,
                          fontWeight: widget.selected || _hovered
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (!widget.dense) ...[
                        const SizedBox(height: 3),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          width: widget.selected ? 13 : (_hovered ? 8 : 0),
                          height: 2,
                          decoration: BoxDecoration(
                            color: widget.selected ? _lime : _cyan,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog({required this.adminPin});
  final String adminPin;

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _unlock() {
    Navigator.of(context).pop(_controller.text == widget.adminPin);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Admin access'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Enter your PIN',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => _unlock(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _unlock, child: const Text('Unlock')),
        ],
      );
}

class _AdminSignInDialog extends StatefulWidget {
  const _AdminSignInDialog({required this.store});
  final PortfolioStore store;

  @override
  State<_AdminSignInDialog> createState() => _AdminSignInDialogState();
}

class _AdminSignInDialogState extends State<_AdminSignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.signIn(_email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Check your admin email and password.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Admin sign in'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Admin email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
        ],
      );
}

class _SiteNav extends StatelessWidget {
  const _SiteNav({
    required this.data,
    required this.compact,
    required this.dense,
    required this.onAdmin,
  });
  final PortfolioData data;
  final bool compact;
  final bool dense;
  final VoidCallback onAdmin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 20 : 44,
          dense ? 3 : 14,
          compact ? 20 : 44,
          dense ? 3 : 12,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Row(
              children: [
                _BrandMark(data: data, compact: compact, dense: dense),
                const Spacer(),
                if (!compact) const _StatusChip(),
                if (!compact) const SizedBox(width: 10),
                IconButton(
                  onPressed: onAdmin,
                  tooltip: 'Admin dashboard',
                  constraints: dense
                      ? const BoxConstraints.tightFor(width: 36, height: 36)
                      : null,
                  padding: dense ? EdgeInsets.zero : null,
                  icon: Icon(
                    Icons.tune_rounded,
                    size: dense ? 18 : 20,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({
    required this.data,
    required this.compact,
    this.dense = false,
  });
  final PortfolioData data;
  final bool compact;
  final bool dense;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: dense ? 32 : 42,
            height: dense ? 32 : 42,
            decoration: BoxDecoration(
              color: _lime,
              borderRadius: BorderRadius.circular(dense ? 11 : 15),
              boxShadow: [
                BoxShadow(
                  color: _lime.withValues(alpha: .25),
                  blurRadius: dense ? 12 : 22,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(dense ? 11 : 15),
              child: _AdaptiveImage(
                source: data.brandImage,
                fallback: const Icon(
                  Icons.blur_on_rounded,
                  color: _ink,
                  size: 27,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            compact ? data.siteTitle.split(' ').first : data.siteTitle,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
              fontSize: dense ? 12 : null,
            ),
          ),
        ],
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: const Row(
          children: [
            Icon(Icons.circle, color: _lime, size: 7),
            SizedBox(width: 8),
            Text(
              'Available for select projects',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      );
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.data,
    required this.compact,
    required this.onWork,
    required this.onContact,
  });
  final PortfolioData data;
  final bool compact;
  final VoidCallback onWork;
  final VoidCallback onContact;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 22 : 54,
              compact ? 26 : 52,
              compact ? 22 : 54,
              compact ? 74 : 108,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Eyebrow(data.role),
                      const SizedBox(height: 22),
                      _Headline(data.headline, compact: true),
                      const SizedBox(height: 18),
                      Text(
                        data.summary,
                        style: const TextStyle(
                          color: _muted,
                          height: 1.75,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _HeroButtons(onWork: onWork, onContact: onContact),
                      const SizedBox(height: 36),
                      _HeroVisual(data: data, compact: true),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          _Avatar(data: data, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  data.location,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_downward_rounded,
                            color: _lime,
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 36),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Eyebrow(data.role),
                              const SizedBox(height: 28),
                              _Headline(data.headline, compact: false),
                              const SizedBox(height: 22),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 500),
                                child: Text(
                                  data.summary,
                                  style: const TextStyle(
                                    color: _muted,
                                    height: 1.8,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              _HeroButtons(
                                  onWork: onWork, onContact: onContact),
                              const SizedBox(height: 58),
                              Row(
                                children: [
                                  _Avatar(data: data, size: 46),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        data.location,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 24),
                                  Container(
                                    width: 1,
                                    height: 34,
                                    color: Colors.white12,
                                  ),
                                  const SizedBox(width: 24),
                                  const Icon(
                                    Icons.south_east_rounded,
                                    color: _lime,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'Scroll to explore',
                                    style:
                                        TextStyle(color: _muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 30),
                      Expanded(
                        flex: 9,
                        child: _HeroVisual(data: data, compact: false),
                      ),
                    ],
                  ),
          ),
        ),
      );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 24, height: 1, color: _lime),
          const SizedBox(width: 10),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: _lime,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ],
      );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text, {required this.compact});
  final String text;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final pieces = text.split('\n');
    final spans = <TextSpan>[];
    for (var i = 0; i < pieces.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.add(
        TextSpan(
          text: pieces[i],
          style: i == pieces.length - 1 ? const TextStyle(color: _lime) : null,
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: compact ? 52 : 74,
        height: .99,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? -3.7 : -5.4,
        color: Colors.white,
      ),
    );
  }
}

class _HeroButtons extends StatelessWidget {
  const _HeroButtons({required this.onWork, required this.onContact});
  final VoidCallback onWork;
  final VoidCallback onContact;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _AnimatedCtaButton(
            primary: true,
            onPressed: onWork,
            icon: Icons.arrow_outward_rounded,
            label: 'Explore my work',
          ),
          _AnimatedCtaButton(
            primary: false,
            onPressed: onContact,
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Let’s talk',
          ),
        ],
      );
}

class _AnimatedCtaButton extends StatefulWidget {
  const _AnimatedCtaButton({
    required this.primary,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool primary;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  State<_AnimatedCtaButton> createState() => _AnimatedCtaButtonState();
}

class _AnimatedCtaButtonState extends State<_AnimatedCtaButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedScale(
            scale: _pressed ? .94 : (_hovered ? 1.065 : 1),
            duration: Duration(milliseconds: _pressed ? 100 : 200),
            curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: _hovered || _pressed
                    ? [
                        BoxShadow(
                          color: (widget.primary ? _lime : _cyan).withValues(
                            alpha: _pressed ? .32 : .24,
                          ),
                          blurRadius: _pressed ? 14 : 30,
                          spreadRadius: _hovered ? 2 : 0,
                        ),
                      ]
                    : const [],
              ),
              child: widget.primary
                  ? FilledButton.icon(
                      onPressed: widget.onPressed,
                      icon: AnimatedRotation(
                        turns: _hovered ? .05 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: Icon(widget.icon, size: 16),
                      ),
                      label: Text(widget.label),
                      style: FilledButton.styleFrom(
                        backgroundColor: _lime,
                        foregroundColor: _ink,
                        elevation: _hovered ? 6 : 0,
                        shadowColor: _lime,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 19,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: widget.onPressed,
                      icon: AnimatedRotation(
                        turns: _hovered ? -.05 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: Icon(widget.icon, size: 16),
                      ),
                      label: Text(widget.label),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: _hovered || _pressed
                              ? _cyan.withValues(alpha: .72)
                              : Colors.white.withValues(alpha: .15),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 19,
                          vertical: 16,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({required this.data, required this.compact});
  final PortfolioData data;
  final bool compact;
  @override
  Widget build(BuildContext context) => _FloatMotion(
        child: AspectRatio(
          aspectRatio: compact ? 1.05 : .91,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .13)),
                  boxShadow: [
                    BoxShadow(
                      color: _violet.withValues(alpha: .12),
                      blurRadius: 80,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(33),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AdaptiveImage(
                        source: data.heroImage,
                        fallback: const _HeroArtwork(),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .08),
                              Colors.transparent,
                              Colors.black.withValues(alpha: .6),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        top: 20,
                        child: _TinyPill(
                          icon: Icons.auto_awesome,
                          text: 'DESIGN IN MOTION',
                        ),
                      ),
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 24,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.name.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w700,
                                      color: _lime,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  const Text(
                                    'Curious by nature.\nIntentional by design.',
                                    style: TextStyle(
                                      fontSize: 19,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.north_east_rounded,
                                  size: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: compact ? -9 : -28,
                top: compact ? 68 : 88,
                child: _OrbitBadge(),
              ),
              Positioned(
                left: compact ? -7 : -23,
                bottom: compact ? 92 : 106,
                child: _GlassStat(),
              ),
            ],
          ),
        ),
      );
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .32),
          border: Border.all(color: Colors.white.withValues(alpha: .18)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: _lime),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _OrbitBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _lime,
          boxShadow: [
            BoxShadow(color: _lime.withValues(alpha: .3), blurRadius: 28),
          ],
        ),
        child: const Icon(Icons.north_east_rounded, color: _ink, size: 23),
      );
}

class _GlassStat extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xD911151D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 25, offset: Offset(0, 10)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: _lime, size: 18),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GOOD ENERGY',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Made to move',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      );
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF222347), Color(0xFF111722), Color(0xFF24403A)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: c.maxWidth * .08,
                top: c.maxHeight * .15,
                child: _SoftGlow(
                  color: _violet.withValues(alpha: .65),
                  size: c.maxWidth * .7,
                ),
              ),
              Positioned(
                right: -c.maxWidth * .16,
                bottom: -c.maxHeight * .12,
                child: _SoftGlow(
                  color: _cyan.withValues(alpha: .36),
                  size: c.maxWidth * .8,
                ),
              ),
              Positioned(
                left: c.maxWidth * .12,
                top: c.maxHeight * .12,
                child: Container(
                  width: c.maxWidth * .76,
                  height: c.maxHeight * .58,
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .22)),
                    borderRadius: BorderRadius.circular(c.maxWidth * .4),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .16),
                        Colors.white.withValues(alpha: .01),
                      ],
                    ),
                  ),
                  transform: Matrix4.rotationZ(-.17),
                ),
              ),
              Positioned(
                left: c.maxWidth * .24,
                top: c.maxHeight * .20,
                child: Container(
                  width: c.maxWidth * .5,
                  height: c.maxWidth * .5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFFEDB4FF),
                        Color(0xFF8C68FF),
                        Color(0x004C4080),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x997F64F5),
                        blurRadius: 52,
                        spreadRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: c.maxWidth * .29,
                top: c.maxHeight * .26,
                child: Container(
                  width: c.maxWidth * .4,
                  height: c.maxWidth * .4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .42),
                      width: 1,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0x77FFFFFF),
                        Color(0x1178DFFF),
                        Color(0x44615BFF),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: c.maxWidth * .17,
                top: c.maxHeight * .16,
                child: Transform.rotate(
                  angle: -.3,
                  child: Icon(
                    Icons.auto_awesome,
                    color: _lime.withValues(alpha: .8),
                    size: 23,
                  ),
                ),
              ),
              Positioned(
                right: c.maxWidth * .16,
                top: c.maxHeight * .27,
                child: Transform.rotate(
                  angle: .27,
                  child: Icon(
                    Icons.add,
                    color: Colors.white.withValues(alpha: .6),
                    size: 30,
                  ),
                ),
              ),
              Positioned(
                left: c.maxWidth * .16,
                bottom: c.maxHeight * .28,
                child: Text(
                  '01 / 04',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .6),
                    fontSize: 9,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.data, required this.size});
  final PortfolioData data;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: data.avatar.isEmpty
              ? Container(
                  color: _panel,
                  alignment: Alignment.center,
                  child: Text(
                    _initials(data.name),
                    style: const TextStyle(
                      color: _lime,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                )
              : _AdaptiveImage(
                  source: data.avatar,
                  fallback: Container(
                    color: _panel,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, color: _lime),
                  ),
                ),
        ),
      );
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part.characters.first.toUpperCase())
    .join();

class _WorkSection extends StatelessWidget {
  const _WorkSection({required this.data});
  final PortfolioData data;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final columns = constraints.maxWidth > 1080
              ? 3
              : (constraints.maxWidth > 700 ? 2 : 1);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1260),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 22 : 54,
                  40,
                  compact ? 22 : 54,
                  76,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTop(
                      kicker: 'A FEW RECENT FAVORITES',
                      title: 'Selected work',
                      trailing:
                          '${data.projects.length.toString().padLeft(2, '0')} PROJECTS',
                    ),
                    const SizedBox(height: 29),
                    if (data.projects.isEmpty)
                      const _EmptyProjects()
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.projects.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: compact ? .93 : .89,
                        ),
                        itemBuilder: (context, index) => _ProjectCard(
                          project: data.projects[index],
                          index: index,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: const Text(
          'Your next project will appear here.',
          style: TextStyle(color: _muted),
        ),
      );
}

class _SectionTop extends StatelessWidget {
  const _SectionTop({required this.kicker, required this.title, this.trailing});
  final String kicker;
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker,
                  style: const TextStyle(
                    color: _lime,
                    letterSpacing: 1.5,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 34,
                    letterSpacing: -1.8,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: _muted,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
            ),
        ],
      );
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({required this.project, required this.index});
  final PortfolioProject project;
  final int index;
  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: () => _openLink(widget.project.url),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            transform: Matrix4.translationValues(0, hover ? -5 : 0, 0),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF10141B),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: hover
                    ? _lime.withValues(alpha: .5)
                    : Colors.white.withValues(alpha: .08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          scale: hover ? 1.055 : 1,
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          child: _AdaptiveImage(
                            source: widget.project.image,
                            fallback: _ProjectArtwork(index: widget.index),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _TinyPill(
                            icon: Icons.circle,
                            text: widget.project.tag.toUpperCase(),
                          ),
                        ),
                        Positioned(
                          right: 11,
                          top: 11,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .28),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              Icons.arrow_outward_rounded,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 14, 5, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.project.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: hover ? .12 : 0,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: const Icon(
                          Icons.north_east,
                          size: 16,
                          color: _lime,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
                  child: Text(
                    widget.project.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ProjectArtwork extends StatelessWidget {
  const _ProjectArtwork({required this.index});
  final int index;
  static const _colors = [
    [Color(0xFF2A4F55), Color(0xFF9CFF95)],
    [Color(0xFF494175), Color(0xFFFFA7D2)],
    [Color(0xFF914F31), Color(0xFFFFDA82)],
    [Color(0xFF22406D), Color(0xFF69C8FF)],
  ];
  @override
  Widget build(BuildContext context) {
    final colors = _colors[index % _colors.length];
    return LayoutBuilder(
      builder: (context, c) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -c.maxWidth * .08,
              top: c.maxHeight * .1,
              child: Transform.rotate(
                angle: -.22 + index * .05,
                child: Container(
                  width: c.maxWidth * .78,
                  height: c.maxHeight * .7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    color: Colors.white.withValues(alpha: .17),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .28),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: c.maxWidth * .1,
              bottom: -c.maxHeight * .25,
              child: Container(
                width: c.maxWidth * .65,
                height: c.maxWidth * .65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[1].withValues(alpha: .85),
                  boxShadow: [
                    BoxShadow(
                      color: colors[1].withValues(alpha: .5),
                      blurRadius: 55,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: c.maxWidth * .15,
              top: c.maxHeight * .22,
              child: Icon(
                [
                  Icons.change_history_rounded,
                  Icons.blur_circular_rounded,
                  Icons.waves_rounded,
                  Icons.crop_free_rounded,
                ][index % 4],
                size: c.maxWidth * .46,
                color: Colors.white.withValues(alpha: .8),
              ),
            ),
            Positioned(
              right: 15,
              bottom: 14,
              child: Text(
                '0${index + 1}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .75),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.data, required this.compact});
  final PortfolioData data;
  final bool compact;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 22 : 54,
              36,
              compact ? 22 : 54,
              90,
            ),
            child: Container(
              padding: EdgeInsets.all(compact ? 22 : 42),
              decoration: BoxDecoration(
                color: const Color(0xFF11151D).withValues(alpha: .8),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A LITTLE ABOUT ME',
                    style: const TextStyle(
                      color: _lime,
                      letterSpacing: 1.5,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (compact) ...[
                    const Text(
                      'Good work should\nfeel like something.',
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.8,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      data.about,
                      style: const TextStyle(
                        color: _muted,
                        height: 1.8,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: data.skills
                          .map((skill) => _SkillChip(skill))
                          .toList(),
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          flex: 11,
                          child: Text(
                            'Good work should\nfeel like something.',
                            style: TextStyle(
                              fontSize: 43,
                              height: 1.08,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 42),
                        Expanded(
                          flex: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.about,
                                style: const TextStyle(
                                  color: _muted,
                                  height: 1.85,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: data.skills
                                    .map((skill) => _SkillChip(skill))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SkillChip extends StatelessWidget {
  const _SkillChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, color: _muted)),
      );
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.data});
  final PortfolioData data;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 75),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF19221D),
                    const Color(0xFF11151D).withValues(alpha: .85),
                  ],
                ),
                border: Border.all(color: _lime.withValues(alpha: .14)),
                borderRadius: BorderRadius.circular(28),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final stacked = c.maxWidth < 700;
                  final copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HAVE A GOOD ONE IN MIND?',
                        style: TextStyle(
                          color: _lime,
                          letterSpacing: 1.5,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Let’s make it\ncome alive.',
                        style: TextStyle(
                          fontSize: stacked ? 38 : 48,
                          height: 1,
                          letterSpacing: -2.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.location,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  );
                  final action = _AnimatedCtaButton(
                    primary: true,
                    onPressed: () => _openLink('mailto:${data.email}'),
                    icon: Icons.arrow_outward_rounded,
                    label: data.email,
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [copy, const SizedBox(height: 24), action],
                        )
                      : Row(
                          children: [
                            Expanded(child: copy),
                            action,
                          ],
                        );
                },
              ),
            ),
          ),
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.data, required this.onAdmin});
  final PortfolioData data;
  final VoidCallback onAdmin;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            child: Column(
              children: [
                Container(
                    height: 1, color: Colors.white.withValues(alpha: .09)),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 570
                      ? Column(
                          children: [
                            _BrandMark(data: data, compact: true),
                            const SizedBox(height: 15),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              children: data.links
                                  .map((link) => _SocialButton(link: link))
                                  .toList(),
                            ),
                            const SizedBox(height: 13),
                            Text(
                              '© ${DateTime.now().year} ${data.name}',
                              style:
                                  const TextStyle(color: _muted, fontSize: 10),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _BrandMark(data: data, compact: false),
                            const Spacer(),
                            Expanded(
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...data.links.map(
                                    (link) => _SocialButton(link: link),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '© ${DateTime.now().year} ${data.name}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: onAdmin,
                                    tooltip: 'Admin dashboard',
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 16,
                                      color: _muted,
                                    ),
                                  ),
                                ],
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.link});
  final PortfolioLink link;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: link.label,
        onPressed: () => _openLink(link.url),
        icon: Icon(_linkIcon(link.label), size: 18, color: _muted),
      );
}

IconData _linkIcon(String label) {
  final value = label.toLowerCase();
  if (value.contains('mail')) return Icons.mail_outline_rounded;
  if (value.contains('phone') || value.contains('mobile'))
    return Icons.phone_iphone_rounded;
  if (value.contains('instagram')) return Icons.camera_alt_outlined;
  if (value.contains('linkedin')) return Icons.work_outline_rounded;
  if (value.contains('github') || value.contains('code'))
    return Icons.code_rounded;
  if (value.contains('youtube')) return Icons.smart_display_outlined;
  return Icons.link_rounded;
}

class _AdaptiveImage extends StatelessWidget {
  const _AdaptiveImage({required this.source, required this.fallback});
  final String source;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    if (source.isEmpty) return fallback;
    try {
      if (source.startsWith('data:image'))
        return Image.memory(
          base64Decode(source.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      return Image.network(
        source,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }
}

class _FloatMotion extends StatefulWidget {
  const _FloatMotion({required this.child});
  final Widget child;
  @override
  State<_FloatMotion> createState() => _FloatMotionState();
}

class _FloatMotionState extends State<_FloatMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, math.sin(controller.value * math.pi) * -8),
          child: Transform.rotate(
            angle: math.sin(controller.value * math.pi * 2) * .012,
            child: child,
          ),
        ),
        child: RepaintBoundary(child: widget.child),
      );
}

class MotionBackdrop extends StatelessWidget {
  const MotionBackdrop({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: const CustomPaint(
          painter: _BackdropPainter(),
          size: Size.infinite,
        ),
      );
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glowA = Offset(size.width * .83, size.height * .1);
    final glowB = Offset(size.width * .12, size.height * .48);
    canvas.drawCircle(
      glowA,
      size.width * .35,
      Paint()
        ..shader = RadialGradient(
          colors: [_violet.withValues(alpha: .105), Colors.transparent],
        ).createShader(
          Rect.fromCircle(center: glowA, radius: size.width * .35),
        ),
    );
    canvas.drawCircle(
      glowB,
      size.width * .28,
      Paint()
        ..shader = RadialGradient(
          colors: [_cyan.withValues(alpha: .05), Colors.transparent],
        ).createShader(
          Rect.fromCircle(center: glowB, radius: size.width * .28),
        ),
    );
    final center = Offset(size.width * .78, size.height * .38);
    final orbitPaint = Paint()
      ..color = Colors.white.withValues(alpha: .045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: math.min(size.width * .72, 900),
        height: 190,
      ),
      orbitPaint,
    );
    final dot = center +
        Offset(
          math.min(size.width * .36, 450),
          0,
        );
    canvas.drawCircle(dot, 3, Paint()..color = _lime.withValues(alpha: .8));
    canvas.drawCircle(dot, 9, Paint()..color = _lime.withValues(alpha: .1));
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

Future<String?> _pickImage() async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1400,
    maxHeight: 1400,
    imageQuality: 78,
  );
  if (image == null) return null;
  final bytes = await image.readAsBytes();
  final extension = image.name.toLowerCase().split('.').last;
  final mime = extension == 'png'
      ? 'image/png'
      : (extension == 'webp' ? 'image/webp' : 'image/jpeg');
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

Future<void> _openLink(String value) async {
  if (value.trim().isEmpty) return;
  final uri = Uri.tryParse(value.trim());
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.store});
  final PortfolioStore store;
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final Map<String, TextEditingController> fields;
  late String avatar;
  late String brandImage;
  late String appIcon;
  late String heroImage;
  late List<PortfolioProject> projects;
  late List<PortfolioLink> links;
  String section = 'Profile';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.store.data;
    final initialFields = {
      'name': d.name,
      'siteTitle': d.siteTitle,
      'role': d.role,
      'headline': d.headline,
      'summary': d.summary,
      'about': d.about,
      'skills': d.skills.join(', '),
      'location': d.location,
      'email': d.email,
      'phone': d.phone,
      if (!widget.store.cloudEnabled) 'pin': d.adminPin,
    };
    fields = {
      for (final entry in initialFields.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    avatar = d.avatar;
    brandImage = d.brandImage;
    appIcon = d.appIcon;
    heroImage = d.heroImage;
    projects = List.of(d.projects);
    links = List.of(d.links);
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.store.save(
        widget.store.data.copyWith(
          name: fields['name']!.text.trim(),
          siteTitle: fields['siteTitle']!.text.trim(),
          role: fields['role']!.text.trim(),
          headline: fields['headline']!.text.trim(),
          summary: fields['summary']!.text.trim(),
          about: fields['about']!.text.trim(),
          skills: fields['skills']!
              .text
              .split(RegExp(r'[,\n]'))
              .map((skill) => skill.trim())
              .where((skill) => skill.isNotEmpty)
              .toList(),
          location: fields['location']!.text.trim(),
          email: fields['email']!.text.trim(),
          phone: fields['phone']!.text.trim(),
          adminPin: widget.store.cloudEnabled
              ? widget.store.data.adminPin
              : (fields['pin']!.text.trim().isEmpty
                  ? widget.store.data.adminPin
                  : fields['pin']!.text.trim()),
          avatar: avatar,
          brandImage: brandImage,
          appIcon: appIcon,
          heroImage: heroImage,
          projects: projects,
          links: links,
        ),
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.store.cloudEnabled
                  ? 'Portfolio changes are now shared with everyone.'
                  : 'Portfolio changes have been saved on this device.',
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ink,
        appBar: AppBar(
          backgroundColor: _ink,
          title: const Text(
            'Portfolio studio',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            if (widget.store.cloudEnabled)
              IconButton(
                tooltip: 'Sign out',
                onPressed: saving
                    ? null
                    : () async {
                        await widget.store.signOut();
                        if (mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.logout_rounded),
              ),
            TextButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(saving ? 'Saving' : 'Save changes'),
              style: TextButton.styleFrom(foregroundColor: _lime),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 800;
            return Row(
              children: [
                if (wide)
                  NavigationRail(
                    extended: c.maxWidth > 1050,
                    backgroundColor: _ink,
                    selectedIndex: _sections.indexOf(section),
                    onDestinationSelected: (i) =>
                        setState(() => section = _sections[i]),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline),
                        label: Text('Profile'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.work_outline),
                        label: Text('Projects'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.link_rounded),
                        label: Text('Links'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Column(
                    children: [
                      if (!wide)
                        SizedBox(
                          height: 56,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: _sections
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(item),
                                      selected: section == item,
                                      onSelected: (_) =>
                                          setState(() => section = item),
                                      selectedColor:
                                          _lime.withValues(alpha: .2),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 36 : 20,
                            18,
                            wide ? 36 : 20,
                            40,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 980),
                              child: _sectionBody(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

  static const _sections = ['Profile', 'Projects', 'Links'];

  Widget _sectionBody() {
    if (section == 'Projects') return _projectsSection();
    if (section == 'Links') return _linksSection();
    return _profileSection();
  }

  Widget _profileSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AdminHeading(
            title: 'Make it yours',
            subtitle:
                'Update the words, images, and contact details that appear on your portfolio.',
          ),
          const SizedBox(height: 24),
          _AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeading(
                  'Website branding',
                  'Change your profile photo, website logo, browser icon, and home image.',
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 820;
                    final avatarCard = _ImageEditorTile(
                      title: 'Profile photo',
                      source: avatar,
                      aspect: 1,
                      onPick: () async {
                        final result = await _pickImage();
                        if (result != null) setState(() => avatar = result);
                      },
                      onRemove: avatar.isEmpty
                          ? null
                          : () => setState(() => avatar = ''),
                    );
                    final brandCard = _ImageEditorTile(
                      title: 'Website logo',
                      source: brandImage,
                      aspect: 1,
                      onPick: () async {
                        final result = await _pickImage();
                        if (result != null) {
                          setState(() => brandImage = result);
                        }
                      },
                      onRemove: brandImage.isEmpty
                          ? null
                          : () => setState(() => brandImage = ''),
                    );
                    final appIconCard = _ImageEditorTile(
                      title: 'Browser tab icon',
                      source: appIcon,
                      aspect: 1,
                      onPick: () async {
                        final result = await _pickImage();
                        if (result != null) setState(() => appIcon = result);
                      },
                      onRemove: appIcon.isEmpty
                          ? null
                          : () => setState(() => appIcon = ''),
                    );
                    final heroCard = _ImageEditorTile(
                      title: 'Home page image',
                      source: heroImage,
                      aspect: 1.8,
                      onPick: () async {
                        final result = await _pickImage();
                        if (result != null) setState(() => heroImage = result);
                      },
                      onRemove: heroImage.isEmpty
                          ? null
                          : () => setState(() => heroImage = ''),
                    );
                    return narrow
                        ? Column(
                            children: [
                              avatarCard,
                              const SizedBox(height: 12),
                              brandCard,
                              const SizedBox(height: 12),
                              appIconCard,
                              const SizedBox(height: 12),
                              heroCard,
                            ],
                          )
                        : Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: avatarCard),
                                  const SizedBox(width: 14),
                                  Expanded(child: brandCard),
                                  const SizedBox(width: 14),
                                  Expanded(child: appIconCard),
                                ],
                              ),
                              const SizedBox(height: 12),
                              heroCard,
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AdminCard(
            child: Column(
              children: [
                const _CardHeading(
                  'Words & details',
                  'These fields update across your website and browser tab.',
                ),
                const SizedBox(height: 17),
                _field('siteTitle', 'Website name'),
                _field('name', 'Your name'),
                _field('role', 'Role / speciality'),
                _field(
                  'headline',
                  'Main headline',
                  maxLines: 2,
                  hint: 'Use a new line to split the headline',
                ),
                _field('summary', 'Short introduction', maxLines: 3),
                _field('about', 'About you', maxLines: 4),
                _field(
                  'skills',
                  'About tags (comma-separated)',
                  hint: 'Art direction, Flutter, Motion design',
                ),
                _field('location', 'Location / availability'),
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 500
                      ? Column(
                          children: [
                            _field('email', 'Email'),
                            _field('phone', 'Phone'),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: _field('email', 'Email')),
                            const SizedBox(width: 12),
                            Expanded(child: _field('phone', 'Phone')),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeading(
                  widget.store.cloudEnabled
                      ? 'Cloud admin access'
                      : 'Admin access',
                  widget.store.cloudEnabled
                      ? 'Your Supabase admin account controls shared portfolio edits.'
                      : 'Change the PIN used to open this dashboard.',
                ),
                const SizedBox(height: 16),
                if (widget.store.cloudEnabled)
                  const Text(
                    'Your changes publish to the shared website when you tap Save changes.',
                    style: TextStyle(color: _muted),
                  )
                else
                  _field(
                    'pin',
                    'New admin PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _projectsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminHeading(
            title: 'Your projects',
            subtitle:
                'Add work, update the details, or change the project imagery.',
            action: FilledButton.icon(
              onPressed: () => _editProject(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add project'),
              style: FilledButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: _ink,
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (projects.isEmpty)
            const _AdminCard(
              child: Text(
                'No projects yet. Add the first one to fill out your work page.',
                style: TextStyle(color: _muted),
              ),
            )
          else
            ...projects.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProjectAdminTile(
                      project: entry.value,
                      onEdit: () => _editProject(index: entry.key),
                      onDelete: () => _confirmDeleteProject(entry.key),
                    ),
                  ),
                ),
        ],
      );

  Widget _linksSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminHeading(
            title: 'Social & contact links',
            subtitle:
                'Your link icons appear in the footer. Add the ones you want visitors to find.',
            action: FilledButton.icon(
              onPressed: _addLink,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add link'),
              style: FilledButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: _ink,
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (links.isEmpty)
            const _AdminCard(
              child: Text(
                'Add a link to show a contact or social icon in your footer.',
                style: TextStyle(color: _muted),
              ),
            )
          else
            ...links.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LinkAdminTile(
                      link: entry.value,
                      onEdit: () => _editLink(entry.key),
                      onDelete: () => setState(() => links.removeAt(entry.key)),
                    ),
                  ),
                ),
          const SizedBox(height: 5),
          const Text(
            'Tip: use full URLs for websites, or mailto: and tel: links for direct contact.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      );

  Widget _field(
    String key,
    String label, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: fields[key],
          maxLines: obscureText ? 1 : maxLines,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Future<void> _editProject({int? index}) async {
    final existing = index == null ? null : projects[index];
    final project = await Navigator.push<PortfolioProject>(
      context,
      MaterialPageRoute(builder: (_) => ProjectEditorPage(project: existing)),
    );
    if (project != null && mounted)
      setState(() {
        if (index == null) {
          projects.add(project);
        } else {
          projects[index] = project;
        }
      });
  }

  Future<void> _confirmDeleteProject(int index) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Remove this project?'),
        content: Text(
          '“${projects[index].title}” will disappear from your portfolio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) setState(() => projects.removeAt(index));
  }

  Future<void> _addLink() async {
    final result = await _linkDialog();
    if (result != null && mounted) setState(() => links.add(result));
  }

  Future<void> _editLink(int index) async {
    final result = await _linkDialog(link: links[index]);
    if (result != null && mounted) setState(() => links[index] = result);
  }

  Future<PortfolioLink?> _linkDialog({PortfolioLink? link}) async {
    return showDialog<PortfolioLink>(
      context: context,
      builder: (_) => _LinkEditorDialog(link: link),
    );
  }
}

class _LinkEditorDialog extends StatefulWidget {
  const _LinkEditorDialog({this.link});
  final PortfolioLink? link;

  @override
  State<_LinkEditorDialog> createState() => _LinkEditorDialogState();
}

class _LinkEditorDialogState extends State<_LinkEditorDialog> {
  late final _label = TextEditingController(text: widget.link?.label ?? '');
  late final _url = TextEditingController(text: widget.link?.url ?? '');

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    final url = _url.text.trim();
    if (label.isEmpty || url.isEmpty) return;
    Navigator.of(context).pop(PortfolioLink(label: label, url: url));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _panel,
        title: Text(widget.link == null ? 'Add a link' : 'Edit link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Instagram, Email, Phone',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save link')),
        ],
      );
}

class _AdminHeading extends StatelessWidget {
  const _AdminHeading({
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => c.maxWidth < 620
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: action!,
                    ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _title()),
                  if (action != null) action!,
                ],
              ),
      );
  Widget _title() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      );
}

class _CardHeading extends StatelessWidget {
  const _CardHeading(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      );
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _panel.withValues(alpha: .72),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
          borderRadius: BorderRadius.circular(21),
        ),
        child: child,
      );
}

class _ImageEditorTile extends StatelessWidget {
  const _ImageEditorTile({
    required this.title,
    required this.source,
    required this.aspect,
    required this.onPick,
    this.onRemove,
  });
  final String title;
  final String source;
  final double aspect;
  final VoidCallback onPick;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 9),
          AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _AdaptiveImage(
                    source: source,
                    fallback: Container(
                      color: const Color(0xFF202631),
                      child: const Center(
                        child:
                            Icon(Icons.image_outlined, color: _muted, size: 27),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: onPick,
                            icon: const Icon(Icons.upload_rounded, size: 16),
                            label: const Text('Choose image'),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: .65),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              textStyle: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        if (onRemove != null) ...[
                          const SizedBox(width: 6),
                          IconButton.filled(
                            onPressed: onRemove,
                            icon: const Icon(Icons.delete_outline, size: 17),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: .65),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ProjectAdminTile extends StatelessWidget {
  const _ProjectAdminTile({
    required this.project,
    required this.onEdit,
    required this.onDelete,
  });
  final PortfolioProject project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => _AdminCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 68,
                child: _AdaptiveImage(
                  source: project.image,
                  fallback: const _ProjectArtwork(index: 1),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    project.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit project',
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete project',
              icon: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF8B8B),
                size: 19,
              ),
            ),
          ],
        ),
      );
}

class _LinkAdminTile extends StatelessWidget {
  const _LinkAdminTile({
    required this.link,
    required this.onEdit,
    required this.onDelete,
  });
  final PortfolioLink link;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => _AdminCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _lime.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_linkIcon(link.label), color: _lime, size: 19),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    link.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit link',
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete link',
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      );
}

class ProjectEditorPage extends StatefulWidget {
  const ProjectEditorPage({super.key, this.project});
  final PortfolioProject? project;
  @override
  State<ProjectEditorPage> createState() => _ProjectEditorPageState();
}

class _ProjectEditorPageState extends State<ProjectEditorPage> {
  late final title = TextEditingController(text: widget.project?.title ?? '');
  late final category = TextEditingController(
    text: widget.project?.category ?? '',
  );
  late final description = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late final url = TextEditingController(text: widget.project?.url ?? '');
  late final tag = TextEditingController(
    text: widget.project?.tag ?? 'PROJECT',
  );
  late String image = widget.project?.image ?? '';
  @override
  void dispose() {
    title.dispose();
    category.dispose();
    description.dispose();
    url.dispose();
    tag.dispose();
    super.dispose();
  }

  void _save() {
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your project a title first.')),
      );
      return;
    }
    Navigator.pop(
      context,
      PortfolioProject(
        title: title.text.trim(),
        category: category.text.trim(),
        description: description.text.trim(),
        image: image,
        url: url.text.trim(),
        tag: tag.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ink,
        appBar: AppBar(
          backgroundColor: _ink,
          title: Text(widget.project == null ? 'Add project' : 'Edit project'),
          actions: [
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
              style: TextButton.styleFrom(foregroundColor: _lime),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImageEditorTile(
                      title: 'Project cover',
                      source: image,
                      aspect: c.maxWidth < 600 ? 1.4 : 2.25,
                      onPick: () async {
                        final result = await _pickImage();
                        if (result != null) setState(() => image = result);
                      },
                      onRemove: image.isEmpty
                          ? null
                          : () => setState(() => image = ''),
                    ),
                    const SizedBox(height: 21),
                    TextField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'Project title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: category,
                      decoration: const InputDecoration(
                        labelText: 'Category & year',
                        hintText: 'Digital experience · 2025',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tag,
                      decoration: const InputDecoration(
                        labelText: 'Small image label',
                        hintText: 'BRANDING',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Project description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Project link',
                        hintText: 'https://…',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
