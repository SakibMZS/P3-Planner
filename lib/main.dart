import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

const String supabaseUrl = 'https://bakolrobvciddpfwwplr.supabase.co';
const String supabaseAnonKey = 'sb_publishable_qoqK8x790vmO-EYADw7YXg_p2WHlfui';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const P3PlannerApp());
}

class P3PlannerApp extends StatelessWidget {
  const P3PlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P-3 Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        cardColor: const Color(0xFF111827),
        primaryColor: const Color(0xFF10B981),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF111827),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ============================================================================
// SHIFT & OPERATIONAL DATE ENGINE (=INT(NOW - 8 HOURS))
// ============================================================================
class ShiftClock {
  static DateTime getOperationalDate([DateTime? now]) {
    final current = now ?? DateTime.now();
    final shifted = current.subtract(const Duration(hours: 8));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  static String getActiveShift([DateTime? now]) {
    final current = now ?? DateTime.now();
    final hour = current.hour;
    return (hour >= 8 && hour < 20) ? 'A' : 'B';
  }

  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String formatDisplayDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  static Map<String, dynamic> getPreviousShift(DateTime opDate, String shift) {
    if (shift == 'B') {
      return {'date': opDate, 'shift': 'A'};
    } else {
      return {'date': opDate.subtract(const Duration(days: 1)), 'shift': 'B'};
    }
  }
}

// ============================================================================
// STATUS DEFINITIONS & MANPOWER MATH
// ============================================================================
class StatusOption {
  final String code;
  final String label;
  final double manpower;
  final Color color;
  final bool isRunning;

  const StatusOption(this.code, this.label, this.manpower, this.color, this.isRunning);
}

const List<StatusOption> kRunningOptions = [
  StatusOption('0.33', '0.33 Op', 0.3333, Color(0xFF10B981), true),
  StatusOption('0.5', '0.5 Op', 0.5000, Color(0xFF10B981), true),
  StatusOption('1', '1 Op', 1.0000, Color(0xFF10B981), true),
  StatusOption('2', '2 Op', 2.0000, Color(0xFF10B981), true),
  StatusOption('3', '3 Op', 3.0000, Color(0xFF10B981), true),
];

const List<String> kOffReasons = [
  'No Demand',
  'Manpower Short*',
  'Machine Problem*',
  'Sample + Mold Test (RND)*',
  'Mold Change*',
  'Product Jam*',
  'Color Change*',
  'Material Shortage*',
  'Mold Problem*',
  'Holiday*',
  'One Machine Idle for Another Machine (Announced)',
  'Others',
];

StatusOption getStatusMeta(String? code) {
  if (code == null || code.isEmpty) {
    return const StatusOption('UNSET', 'Unset', 0.0, Color(0xFF374151), false);
  }
  // Check if it's a running manpower value
  for (final opt in kRunningOptions) {
    if (opt.code == code) return opt;
  }
  // Otherwise it's an OFF reason code
  return StatusOption(code, code, 0.0, const Color(0xFFEF4444), false);
}

String formatManpower(double val) {
  final rounded = (val * 100).round() / 100.0;
  if ((rounded - rounded.round()).abs() < 0.05) {
    return rounded.round().toString();
  }
  return rounded.toStringAsFixed(2);
}

// ============================================================================
// 1. LOGIN SCREEN
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _selectedUser = 'INCHARGE';
  final TextEditingController _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  final List<Map<String, String>> _accounts = [
    {'id': 'INCHARGE', 'name': 'Production Incharge (P-3 Master)'},
    {'id': 'GF-AB', 'name': 'Lineman • GF A-B (11 MCs)'},
    {'id': 'GF-CD', 'name': 'Lineman • GF C-D (13 MCs)'},
    {'id': 'GF-EF', 'name': 'Lineman • GF E-F (12 MCs)'},
    {'id': 'FF-AB', 'name': 'Lineman • FF A-B (15 MCs)'},
    {'id': 'FF-CD', 'name': 'Lineman • FF C-D (10 MCs)'},
  ];

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('p3_users')
          .select()
          .eq('user_id', _selectedUser)
          .single();

      if (res['pin_code'].toString() == _pinController.text.trim()) {
        Supabase.instance.client.rpc('cleanup_old_p3_data').catchError((_) {});
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainWorkspace(user: res),
          ),
        );
      } else {
        setState(() => _error = 'Invalid PIN code. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opDate = ShiftClock.getOperationalDate();
    final activeShift = ShiftClock.getActiveShift();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1F2937), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.precision_manufacturing,
                            color: Color(0xFF10B981), size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'P-3 PLANNER',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'RFL Plastic 3 • MES Shift Control',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0F19),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1F2937)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Op Date: ${ShiftClock.formatDisplayDate(opDate)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SHIFT $activeShift',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SELECT ROLE / LINE ACCOUNT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedUser,
                    dropdownColor: const Color(0xFF1F2937),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0B0F19),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: _accounts
                        .map((a) => DropdownMenuItem(
                              value: a['id'],
                              child: Text(a['name']!,
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUser = v!),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '4-DIGIT SECURITY PIN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    style: const TextStyle(
                        fontSize: 20, letterSpacing: 8, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      filled: true,
                      fillColor: const Color(0xFF0B0F19),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _handleLogin(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'ENTER WORKSPACE',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1),
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
}

// ============================================================================
// 2. MAIN WORKSPACE (ROUTING FOR LINEMAN VS INCHARGE)
// ============================================================================
class MainWorkspace extends StatefulWidget {
  final Map<String, dynamic> user;
  const MainWorkspace({super.key, required this.user});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> {
  late DateTime _selectedDate;
  late String _selectedShift;
  int _inchargeTab = 0;

  List<Map<String, dynamic>> _machines = [];
  Map<String, Map<String, dynamic>> _plansByMc = {};
  Map<String, bool> _lineLocks = {};
  Map<String, dynamic> _roster = {};
  bool _loading = true;

  final List<String> _allLines = ['GF A-B', 'GF C-D', 'GF E-F', 'FF A-B', 'FF C-D'];
  late String _activeLineFilter;

  @override
  void initState() {
    super.initState();
    _selectedDate = ShiftClock.getOperationalDate();
    _selectedShift = ShiftClock.getActiveShift();
    _activeLineFilter = widget.user['assigned_line'] ?? 'GF A-B';
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    final supa = Supabase.instance.client;
    final dateStr = ShiftClock.formatDate(_selectedDate);

    try {
      final mcList = await supa
          .from('p3_machines')
          .select()
          .order('sort_order', ascending: true);

      final planList = await supa
          .from('p3_machine_plans')
          .select()
          .eq('operational_date', dateStr)
          .eq('shift', _selectedShift);

      final lockList = await supa
          .from('p3_line_submissions')
          .select()
          .eq('operational_date', dateStr)
          .eq('shift', _selectedShift);

      final rosterList = await supa
          .from('p3_manpower_roster')
          .select()
          .eq('operational_date', dateStr)
          .eq('shift', _selectedShift);

      final Map<String, Map<String, dynamic>> planMap = {};
      for (final p in planList) {
        planMap[p['mc_position']] = Map<String, dynamic>.from(p);
      }

      final Map<String, bool> lockMap = {};
      for (final l in lockList) {
        lockMap[l['line_name']] = l['is_locked'] == true;
      }

      Map<String, dynamic> activeRoster = {
        'prod_ic': 1,
        'foreman': 1,
        'sic': 5,
        'erp': 1,
        'senior_operator': 4,
        'mold_change_op': 1,
        'mix_recycle_crush': 4,
        'sharp_tools': 1,
        'sub_store': 1,
        'packaging_operator': 0,
        'shrink_wrap_op': 0,
        'printing_op': 0,
        'welding': 0,
        'rework': 0,
        'psi': 0,
        'inventory_op': 1,
        'fg_delivery': 0,
        'floor_housekeeping': 1,
        'hr_transfer': 0,
      };
      if (rosterList.isNotEmpty) {
        activeRoster = Map<String, dynamic>.from(rosterList.first);
      }

      if (mounted) {
        setState(() {
          _machines = List<Map<String, dynamic>>.from(mcList);
          _plansByMc = planMap;
          _lineLocks = lockMap;
          _roster = activeRoster;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    }
  }

  double get _totalMcManpower {
    double sum = 0;
    for (final p in _plansByMc.values) {
      sum += (p['manpower_value'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  int get _roundedMcOperatorCount => _totalMcManpower.round();

  Future<void> _updateMachinePlan(Map<String, dynamic> mc, String statusCode, double manpowerVal) async {
    final lineName = mc['line_name'];
    final isIncharge = widget.user['role'] == 'INCHARGE';
    if (!isIncharge && (_lineLocks[lineName] == true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Line is submitted & locked. Ask Incharge to unlock.')),
      );
      return;
    }

    final dateStr = ShiftClock.formatDate(_selectedDate);
    final payload = {
      'operational_date': dateStr,
      'shift': _selectedShift,
      'mc_position': mc['mc_position'],
      'line_name': lineName,
      'status_code': statusCode,
      'manpower_value': manpowerVal,
      'updated_by': widget.user['user_id'],
      'updated_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _plansByMc[mc['mc_position']] = payload;
    });

    await Supabase.instance.client.from('p3_machine_plans').upsert(payload);
  }

  Future<void> _copyPreviousShiftForLine(String lineName) async {
    final prev = ShiftClock.getPreviousShift(_selectedDate, _selectedShift);
    final prevDateStr = ShiftClock.formatDate(prev['date']);
    final prevShift = prev['shift'];

    final prevPlans = await Supabase.instance.client
        .from('p3_machine_plans')
        .select()
        .eq('operational_date', prevDateStr)
        .eq('shift', prevShift)
        .eq('line_name', lineName);

    if (prevPlans.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No saved data found in $prevDateStr Shift $prevShift for $lineName')),
      );
      return;
    }

    final dateStr = ShiftClock.formatDate(_selectedDate);
    final List<Map<String, dynamic>> batch = [];
    for (final p in prevPlans) {
      batch.add({
        'operational_date': dateStr,
        'shift': _selectedShift,
        'mc_position': p['mc_position'],
        'line_name': lineName,
        'status_code': p['status_code'],
        'manpower_value': p['manpower_value'],
        'updated_by': widget.user['user_id'],
      });
    }

    await Supabase.instance.client.from('p3_machine_plans').upsert(batch);
    await _loadAllData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Copied ${batch.length} machines from Shift $prevShift!')),
    );
  }

  Future<void> _toggleLineLock(String lineName, bool lockState) async {
    final dateStr = ShiftClock.formatDate(_selectedDate);
    await Supabase.instance.client.from('p3_line_submissions').upsert({
      'operational_date': dateStr,
      'shift': _selectedShift,
      'line_name': lineName,
      'is_locked': lockState,
      'submitted_at': DateTime.now().toIso8601String(),
    });
    setState(() {
      _lineLocks[lineName] = lockState;
    });
  }

  Future<void> _saveRosterField(String key, int value) async {
    final dateStr = ShiftClock.formatDate(_selectedDate);
    setState(() {
      _roster[key] = value < 0 ? 0 : value;
    });

    final payload = {
      'operational_date': dateStr,
      'shift': _selectedShift,
      'prod_ic': _roster['prod_ic'] ?? 1,
      'foreman': _roster['foreman'] ?? 1,
      'sic': _roster['sic'] ?? 5,
      'erp': _roster['erp'] ?? 1,
      'senior_operator': _roster['senior_operator'] ?? 4,
      'mold_change_op': _roster['mold_change_op'] ?? 1,
      'mix_recycle_crush': _roster['mix_recycle_crush'] ?? 4,
      'sharp_tools': _roster['sharp_tools'] ?? 1,
      'sub_store': _roster['sub_store'] ?? 1,
      'packaging_operator': _roster['packaging_operator'] ?? 0,
      'shrink_wrap_op': _roster['shrink_wrap_op'] ?? 0,
      'printing_op': _roster['printing_op'] ?? 0,
      'welding': _roster['welding'] ?? 0,
      'rework': _roster['rework'] ?? 0,
      'psi': _roster['psi'] ?? 0,
      'inventory_op': _roster['inventory_op'] ?? 1,
      'fg_delivery': _roster['fg_delivery'] ?? 0,
      'floor_housekeeping': _roster['floor_housekeeping'] ?? 1,
      'hr_transfer': _roster['hr_transfer'] ?? 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await Supabase.instance.client.from('p3_manpower_roster').upsert(payload);
  }

  Future<void> _copyPreviousRoster() async {
    final prev = ShiftClock.getPreviousShift(_selectedDate, _selectedShift);
    final prevDateStr = ShiftClock.formatDate(prev['date']);
    final prevShift = prev['shift'];

    final res = await Supabase.instance.client
        .from('p3_manpower_roster')
        .select()
        .eq('operational_date', prevDateStr)
        .eq('shift', prevShift);

    if (res.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No previous roster found for $prevDateStr Shift $prevShift')),
      );
      return;
    }

    final prevRow = Map<String, dynamic>.from(res.first);
    prevRow['operational_date'] = ShiftClock.formatDate(_selectedDate);
    prevRow['shift'] = _selectedShift;
    prevRow['updated_at'] = DateTime.now().toIso8601String();

    await Supabase.instance.client.from('p3_manpower_roster').upsert(prevRow);
    await _loadAllData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pulled Incharge Roster from $prevDateStr Shift $prevShift!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIncharge = widget.user['role'] == 'INCHARGE';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('P-3 PLANNER',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.user['user_id'],
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Text(
              'Op Date: ${ShiftClock.formatDisplayDate(_selectedDate)} • Shift $_selectedShift',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedShift = _selectedShift == 'A' ? 'B' : 'A';
              });
              _loadAllData();
            },
            icon: const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF06B6D4)),
            label: Text('Shift $_selectedShift',
                style: const TextStyle(
                    color: Color(0xFF06B6D4), fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 19),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 31)),
                lastDate: DateTime.now().add(const Duration(days: 7)),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
                _loadAllData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadAllData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20, color: Color(0xFFEF4444)),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isIncharge
              ? _buildInchargeBody()
              : _buildLineEntryView(widget.user['assigned_line'], false),
      bottomNavigationBar: isIncharge
          ? BottomNavigationBar(
              currentIndex: _inchargeTab,
              backgroundColor: const Color(0xFF111827),
              selectedItemColor: const Color(0xFF10B981),
              unselectedItemColor: const Color(0xFF9CA3AF),
              onTap: (i) => setState(() => _inchargeTab = i),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_customize),
                  label: 'Executive KPI',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.precision_manufacturing),
                  label: '61 MCs Matrix',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.groups),
                  label: 'P-3 Manpower (19)',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildInchargeBody() {
    if (_inchargeTab == 0) return _buildExecutiveDashboard();
    if (_inchargeTab == 1) {
      return Column(
        children: [
          Container(
            color: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _allLines.map((line) {
                  final active = _activeLineFilter == line;
                  final locked = _lineLocks[line] == true;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(line),
                          const SizedBox(width: 4),
                          Icon(
                            locked ? Icons.check_circle : Icons.schedule,
                            size: 14,
                            color: locked
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      selected: active,
                      selectedColor: const Color(0xFF10B981).withOpacity(0.25),
                      onSelected: (_) => setState(() => _activeLineFilter = line),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(child: _buildLineEntryView(_activeLineFilter, true)),
        ],
      );
    }
    return _buildManpowerRosterView();
  }

  // ==========================================================================
  // VIEW A: EXECUTIVE COMMAND CENTER (INCHARGE TAB 1)
  // ==========================================================================
  Widget _buildExecutiveDashboard() {
    int runningCount = 0;
    Map<String, int> statusCounts = {};
    double gfManpower = 0;
    double ffManpower = 0;

    for (final mc in _machines) {
      final p = _plansByMc[mc['mc_position']];
      if (p != null) {
        final code = p['status_code'] as String;
        final meta = getStatusMeta(code);
        if (meta.isRunning) runningCount++;
        statusCounts[code] = (statusCounts[code] ?? 0) + 1;

        final mp = (p['manpower_value'] as num?)?.toDouble() ?? 0.0;
        if (mc['floor_name'] == 'GF') {
          gfManpower += mp;
        } else {
          ffManpower += mp;
        }
      }
    }

    final utilization = _machines.isEmpty ? 0.0 : (runningCount / 61.0) * 100.0;
    final totalIndirect = (_roster['prod_ic'] ?? 1) +
        (_roster['foreman'] ?? 1) +
        (_roster['sic'] ?? 5) +
        (_roster['erp'] ?? 1) +
        (_roster['senior_operator'] ?? 4) +
        (_roster['mold_change_op'] ?? 1) +
        (_roster['mix_recycle_crush'] ?? 4) +
        (_roster['sharp_tools'] ?? 1) +
        (_roster['sub_store'] ?? 1) +
        (_roster['packaging_operator'] ?? 0) +
        (_roster['shrink_wrap_op'] ?? 0) +
        (_roster['printing_op'] ?? 0) +
        (_roster['welding'] ?? 0) +
        (_roster['rework'] ?? 0) +
        (_roster['psi'] ?? 0) +
        (_roster['inventory_op'] ?? 1) +
        (_roster['fg_delivery'] ?? 0) +
        (_roster['floor_housekeeping'] ?? 1) +
        (_roster['hr_transfer'] ?? 0);

    final grandTotalManpower = _roundedMcOperatorCount + totalIndirect;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.65,
          children: [
            _kpiCard('RUNNING MCs', '$runningCount / 61',
                '${utilization.toStringAsFixed(1)}% Plant Util.', const Color(0xFF10B981)),
            _kpiCard('MC OPERATORS', '$_roundedMcOperatorCount',
                'Exact Sum: ${formatManpower(_totalMcManpower)}', const Color(0xFF06B6D4)),
            _kpiCard('FLOOR SPLIT (OP)', 'GF: ${formatManpower(gfManpower)}',
                'FF: ${formatManpower(ffManpower)} Operators', const Color(0xFFF59E0B)),
            _kpiCard('TOTAL P-3 MANPOWER', '$grandTotalManpower',
                '$_roundedMcOperatorCount Direct + $totalIndirect Indirect', const Color(0xFFA855F7)),
          ],
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F2937)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LINE SUBMISSION & MANPOWER SUMMARY',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF9CA3AF))),
              const SizedBox(height: 12),
              ..._allLines.map((line) {
                final lineMcs =
                    _machines.where((m) => m['line_name'] == line).toList();
                int planned = 0;
                int running = 0;
                double lineMp = 0;
                for (final m in lineMcs) {
                  final p = _plansByMc[m['mc_position']];
                  if (p != null) {
                    planned++;
                    if (getStatusMeta(p['status_code']).isRunning) running++;
                    lineMp += (p['manpower_value'] as num?)?.toDouble() ?? 0.0;
                  }
                }
                final isLocked = _lineLocks[line] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        isLocked ? Icons.lock : Icons.lock_open,
                        size: 16,
                        color: isLocked
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(line,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      Text('Run: $running/${lineMcs.length}',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF9CA3AF))),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${formatManpower(lineMp)} Op',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF06B6D4),
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Text('$planned/${lineMcs.length}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: planned == lineMcs.length
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B))),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F2937)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('STATUS & REASON BREAKDOWN',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF9CA3AF))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: statusCounts.entries.map((entry) {
                  final meta = getStatusMeta(entry.key);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: meta.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: meta.color.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: TextStyle(
                          color: meta.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: _copyWhatsAppSummary,
          icon: const Icon(Icons.copy, color: Colors.black),
          label: const Text('COPY FULL P-3 SHIFT REPORT (WHATSAPP / EXCEL)',
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String title, String mainValue, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Text(mainValue,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  // ==========================================================================
  // VIEW B: LINE MACHINE ENTRY (USED BY LINEMEN & INCHARGE OVERRIDE)
  // ==========================================================================
  Widget _buildLineEntryView(String lineName, bool isIncharge) {
    final lineMcs = _machines.where((m) => m['line_name'] == lineName).toList();
    final isLocked = _lineLocks[lineName] == true;

    int completed = 0;
    double lineManpower = 0;
    for (final m in lineMcs) {
      final p = _plansByMc[m['mc_position']];
      if (p != null) {
        completed++;
        lineManpower += (p['manpower_value'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$lineName • $completed/${lineMcs.length} MCs Set',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'Line Operators: ${formatManpower(lineManpower)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: (!isIncharge && isLocked)
                    ? null
                    : () => _copyPreviousShiftForLine(lineName),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Pull Last Shift', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  if (isIncharge) {
                    _toggleLineLock(lineName, !isLocked);
                  } else if (!isLocked && completed == lineMcs.length) {
                    _toggleLineLock(lineName, true);
                  } else if (!isLocked) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Please select status for all machines in this line first.')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLocked
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                ),
                icon: Icon(isLocked ? Icons.lock : Icons.check_circle, size: 16),
                label: Text(
                  isIncharge
                      ? (isLocked ? 'Unlock' : 'Lock Line')
                      : (isLocked ? 'Locked' : 'Submit'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lineMcs.length,
            itemBuilder: (context, idx) {
              final mc = lineMcs[idx];
              final plan = _plansByMc[mc['mc_position']];
              final selectedCode = plan?['status_code'] as String?;

              return _MachinePlanCard(
                mc: mc,
                selectedCode: selectedCode,
                onUpdate: (code, mp) => _updateMachinePlan(mc, code, mp),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // VIEW C: INCHARGE 19-ROLE P-3 MANPOWER ROSTER (GROUPED)
  // ==========================================================================
  Widget _buildManpowerRosterView() {
    final groups = [
      {
        'title': '1. FLOOR LEADERSHIP & ADMIN',
        'items': [
          {'key': 'prod_ic', 'label': 'Prod IC'},
          {'key': 'foreman', 'label': 'Foreman'},
          {'key': 'sic', 'label': 'SIC'},
          {'key': 'erp', 'label': 'ERP'},
        ]
      },
      {
        'title': '2. DIRECT MACHINE & TECHNICAL',
        'items': [
          {'key': '_auto_mc', 'label': 'MC Operator (Auto from 61 MCs)'},
          {'key': 'senior_operator', 'label': 'Senior Operator'},
          {'key': 'mold_change_op', 'label': 'Mold Change Op'},
        ]
      },
      {
        'title': '3. MATERIAL & UTILITY SUPPORT',
        'items': [
          {'key': 'mix_recycle_crush', 'label': 'Mix/Recycle/Crush'},
          {'key': 'sharp_tools', 'label': 'Sharp Tools'},
          {'key': 'sub_store', 'label': 'Sub Store'},
        ]
      },
      {
        'title': '4. POST-MOLDING & QUALITY',
        'items': [
          {'key': 'packaging_operator', 'label': 'Packaging Operator'},
          {'key': 'shrink_wrap_op', 'label': 'Shrink-wrap Op'},
          {'key': 'printing_op', 'label': 'Printing Op'},
          {'key': 'welding', 'label': 'Welding'},
          {'key': 'rework', 'label': 'Rework'},
          {'key': 'psi', 'label': 'PSI'},
        ]
      },
      {
        'title': '5. LOGISTICS, HOUSEKEEPING & HR',
        'items': [
          {'key': 'inventory_op', 'label': 'Inventory Op'},
          {'key': 'fg_delivery', 'label': 'FG Delivery'},
          {'key': 'floor_housekeeping', 'label': 'Floor Housekeeping'},
          {'key': 'hr_transfer', 'label': 'HR Transfer'},
        ]
      },
    ];

    int totalRoster = _roundedMcOperatorCount;
    _roster.forEach((k, v) {
      if (v is int) totalRoster += v;
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL P-3 BUILDING MANPOWER',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9CA3AF))),
                  const SizedBox(height: 4),
                  Text('$totalRoster Personnel',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF10B981))),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _copyPreviousRoster,
                icon: const Icon(Icons.history, size: 18, color: Colors.black),
                label: const Text('Pull Last Shift',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...groups.map((g) {
          final items = g['items'] as List<Map<String, String>>;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g['title'] as String,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF06B6D4),
                        letterSpacing: 1.0)),
                const Divider(color: Color(0xFF1F2937), height: 20),
                ...items.map((item) {
                  final key = item['key']!;
                  final label = item['label']!;
                  if (key == '_auto_mc') {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981))),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_roundedMcOperatorCount (Raw: ${formatManpower(_totalMcManpower)})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final val = (_roster[key] as int?) ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(label,
                                style: const TextStyle(fontSize: 14))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Color(0xFF9CA3AF)),
                          onPressed: () => _saveRosterField(key, val - 1),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '$val',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF10B981)),
                          onPressed: () => _saveRosterField(key, val + 1),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _copyWhatsAppSummary() {
    final sb = StringBuffer();
    sb.writeln('*P-3 PLANNER | SHIFT REPORT*');
    sb.writeln(
        'Date: ${ShiftClock.formatDisplayDate(_selectedDate)} | Shift: $_selectedShift');
    sb.writeln('--------------------------------');
    sb.writeln('*1. FLOOR LEADERSHIP & ADMIN*');
    sb.writeln('Prod IC: ${_roster['prod_ic'] ?? 1}');
    sb.writeln('Foreman: ${_roster['foreman'] ?? 1}');
    sb.writeln('SIC: ${_roster['sic'] ?? 5}');
    sb.writeln('ERP: ${_roster['erp'] ?? 1}');
    sb.writeln('');
    sb.writeln('*2. DIRECT MACHINE & TECHNICAL*');
    sb.writeln('MC Operator: $_roundedMcOperatorCount');
    sb.writeln('Senior Operator: ${_roster['senior_operator'] ?? 4}');
    sb.writeln('Mold Change Op: ${_roster['mold_change_op'] ?? 1}');
    sb.writeln('');
    sb.writeln('*3. MATERIAL & UTILITY SUPPORT*');
    sb.writeln('Mix/Recycle/Crush: ${_roster['mix_recycle_crush'] ?? 4}');
    sb.writeln('Sharp Tools: ${_roster['sharp_tools'] ?? 1}');
    sb.writeln('Sub Store: ${_roster['sub_store'] ?? 1}');
    sb.writeln('');
    sb.writeln('*4. POST-MOLDING & QUALITY*');
    sb.writeln('Packaging Operator: ${_roster['packaging_operator'] ?? 0}');
    sb.writeln('Shrink-wrap Op: ${_roster['shrink_wrap_op'] ?? 0}');
    sb.writeln('Printing Op: ${_roster['printing_op'] ?? 0}');
    sb.writeln('Welding: ${_roster['welding'] ?? 0}');
    sb.writeln('Rework: ${_roster['rework'] ?? 0}');
    sb.writeln('PSI: ${_roster['psi'] ?? 0}');
    sb.writeln('');
    sb.writeln('*5. LOGISTICS, HOUSEKEEPING & HR*');
    sb.writeln('Inventory Op: ${_roster['inventory_op'] ?? 1}');
    sb.writeln('FG Delivery: ${_roster['fg_delivery'] ?? 0}');
    sb.writeln('Floor Housekeeping: ${_roster['floor_housekeeping'] ?? 1}');
    sb.writeln('HR Transfer: ${_roster['hr_transfer'] ?? 0}');

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Full P-3 Shift Report copied to clipboard!')),
    );
  }
}

// ============================================================================
// EXPANDABLE MACHINE CARD WITH RUNNING / OFF CONDITIONAL DROPDOWNS
// ============================================================================
class _MachinePlanCard extends StatefulWidget {
  final Map<String, dynamic> mc;
  final String? selectedCode;
  final Function(String code, double manpower) onUpdate;

  const _MachinePlanCard({
    required this.mc,
    required this.selectedCode,
    required this.onUpdate,
  });

  @override
  State<_MachinePlanCard> createState() => _MachinePlanCardState();
}

class _MachinePlanCardState extends State<_MachinePlanCard> {
  bool _showSmartManu = false;

  @override
  Widget build(BuildContext context) {
    final meta = getStatusMeta(widget.selectedCode);
    // Determine main mode: 'RUNNING', 'OFF', or null (unset)
    String? currentMode;
    if (widget.selectedCode != null) {
      currentMode = meta.isRunning ? 'RUNNING' : 'OFF';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.selectedCode != null
              ? meta.color.withOpacity(0.55)
              : const Color(0xFF1F2937),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.mc['mc_position'],
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _showSmartManu = !_showSmartManu),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: Color(0xFF9CA3AF)),
                      if (_showSmartManu) ...[
                        const SizedBox(width: 5),
                        Text(
                          widget.mc['smart_manu'],
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF06B6D4),
                              fontWeight: FontWeight.bold),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: meta.color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  meta.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: meta.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Step 1: Running vs OFF Toggle Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Default to '1' operator when switching to Running if previously OFF or unset
                    if (currentMode != 'RUNNING') {
                      widget.onUpdate('1', 1.0);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentMode == 'RUNNING'
                        ? const Color(0xFF10B981)
                        : const Color(0xFF0B0F19),
                    foregroundColor: currentMode == 'RUNNING'
                        ? Colors.black
                        : const Color(0xFFD1D5DB),
                    side: BorderSide(
                      color: currentMode == 'RUNNING'
                          ? const Color(0xFF10B981)
                          : const Color(0xFF1F2937),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('RUNNING',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Default to first OFF reason ('No Demand') when switching to OFF
                    if (currentMode != 'OFF') {
                      widget.onUpdate(kOffReasons[0], 0.0);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentMode == 'OFF'
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF0B0F19),
                    foregroundColor: currentMode == 'OFF'
                        ? Colors.black
                        : const Color(0xFFD1D5DB),
                    side: BorderSide(
                      color: currentMode == 'OFF'
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF1F2937),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('OFF',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          // Step 2: Conditional Dropdown based on Running vs OFF selection
          if (currentMode == 'RUNNING') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: kRunningOptions.any((o) => o.code == widget.selectedCode)
                  ? widget.selectedCode
                  : '1',
              dropdownColor: const Color(0xFF1F2937),
              decoration: InputDecoration(
                labelText: 'Allocated Manpower',
                labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                filled: true,
                fillColor: const Color(0xFF0B0F19),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1F2937)),
                ),
              ),
              items: kRunningOptions
                  .map((opt) => DropdownMenuItem(
                        value: opt.code,
                        child: Text('${opt.label} Operator',
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  final opt = kRunningOptions.firstWhere((o) => o.code == val);
                  widget.onUpdate(opt.code, opt.manpower);
                }
              },
            ),
          ] else if (currentMode == 'OFF') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: kOffReasons.contains(widget.selectedCode)
                  ? widget.selectedCode
                  : kOffReasons[0],
              dropdownColor: const Color(0xFF1F2937),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'OFF / Stoppage Reason',
                labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                filled: true,
                fillColor: const Color(0xFF0B0F19),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1F2937)),
                ),
              ),
              items: kOffReasons
                  .map((reason) => DropdownMenuItem(
                        value: reason,
                        child: Text(reason,
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  widget.onUpdate(val, 0.0);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
