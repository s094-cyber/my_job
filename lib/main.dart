import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pattern_lock/pattern_lock.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyJobApp());
}

// ==========================================
// 1. DATABASE HELPER (التخزين الدائم)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('my_job.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section TEXT NOT NULL,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        brand TEXT NOT NULL,
        price REAL NOT NULL,
        image_path TEXT,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        section TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount REAL NOT NULL,
        final_amount REAL NOT NULL,
        status TEXT NOT NULL, -- 'cart', 'pending', 'delivered'
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        amount_paid REAL NOT NULL,
        payment_date TEXT NOT NULL,
        remaining REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
  }

  // Backup & Restore
  Future<String> backupDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'my_job.db');
    final dbFile = File(path);

    final downloadsDir = await getExternalStorageDirectory();
    final backupPath = p.join(downloadsDir!.path, 'MY_JOB_BACKUP.db');
    await dbFile.copy(backupPath);
    return backupPath;
  }

  Future<bool> restoreDatabase() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File backupFile = File(result.files.single.path!);
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'my_job.db');
      await backupFile.copy(path);
      return true;
    }
    return false;
  }
}

// ==========================================
// 2. MAIN APP & THEME CONFIGURATION
// ==========================================
class MyJobApp extends StatelessWidget {
  const MyJobApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY JOB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF9F6F0),
        primaryColor: const Color(0xFFD4A373),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFFD4A373),
          secondary: const Color(0xFFCCD5AE),
        ),
        fontFamily: 'Roboto',
      ),
      home: const PatternLockScreen(),
    );
  }
}

// ==========================================
// 3. PATTERN LOCK SCREEN (شاشة القفل)
// ==========================================
class PatternLockScreen extends StatefulWidget {
  const PatternLockScreen({Key? key}) : super(key: key);

  @override
  _PatternLockScreenState createState() => _PatternLockScreenState();
}

class _PatternLockScreenState extends State<PatternLockScreen> {
  final List<int> _correctPattern = [0, 1, 2, 4, 6, 7, 8];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'تطبيق MY JOB',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFD4A373)),
          ),
          const SizedBox(height: 10),
          const Text('أدخل النمط لفتح التطبيق', style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 40),
          SizedBox(
            height: 300,
            child: PatternLock(
              selectedColor: const Color(0xFFD4A373),
              pointRadius: 12,
              showInput: true,
              dimension: 3,
              relativePadding: 0.7,
              selectThreshold: 25,
              onInputComplete: (List<int> input) {
                if (input.length == _correctPattern.length &&
                    input.every((element) => _correctPattern.contains(element))) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('النمط غير صحيح، حاول مجدداً')),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. HOME SCREEN (اختيار ALORA أو FLORA)
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MY JOB - القائمة الرئيسية', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFD4A373),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            onPressed: () async {
              String path = await DatabaseHelper.instance.backupDatabase();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم حفظ النسخة الاحتياطية في: $path')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: () async {
              bool restored = await DatabaseHelper.instance.restoreDatabase();
              if (restored) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم استرجاع قاعدة البيانات بنجاح')),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSectionCard(
              context,
              title: 'ALORA',
              subtitle: 'قسم البيجامات النسائية',
              color: const Color(0xFFE8D5C4),
              icon: Icons.checkroom,
              section: 'ALORA',
            ),
            _buildSectionCard(
              context,
              title: 'FLORA',
              subtitle: 'قسم المكياج والعناية',
              color: const Color(0xFFF2D1D1),
              icon: Icons.face,
              section: 'FLORA',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required String section,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SectionDashboard(section: section)),
        );
      },
      child: Container(
        width: 300,
        height: 350,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: const Color(0xFF6B4F4F)),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF6B4F4F))),
            const SizedBox(height: 10),
            Text(subtitle, style: const TextStyle(fontSize: 16, color: Color(0xFF6B4F4F))),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. DASHBOARD SCREEN (لوحة العرض للتابلت)
// ==========================================
class SectionDashboard extends StatefulWidget {
  final String section;
  const SectionDashboard({Key? key, required this.section}) : super(key: key);

  @override
  _SectionDashboardState createState() => _SectionDashboardState();
}

class _SectionDashboardState extends State<SectionDashboard> {
  int? _selectedCategoryId;
  String _searchQuery = '';
  Map<int, int> _cart = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.section} - العرض المباشر'),
        backgroundColor: widget.section == 'ALORA' ? const Color(0xFFD4A373) : const Color(0xFFE5989B),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () => _openCartDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => OrdersManagementScreen(section: widget.section)),
              );
            },
          )
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('المجلدات / التصنيفات', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFFD4A373)),
                      onPressed: _addCategoryDialog,
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _getCategories(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final categories = snapshot.data!;
                        return ListView.builder(
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            final isSelected = _selectedCategoryId == cat['id'];
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: const Color(0xFFF9F6F0),
                              title: Text(cat['name']),
                              leading: const Icon(Icons.folder_open),
                              onTap: () {
                                setState(() {
                                  _selectedCategoryId = cat['id'];
                                });
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                onPressed: () => _deleteCategory(cat['id']),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث عن منتج بالاسم أو الماركة...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('المنتجات المعروضة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A373)),
                        onPressed: _selectedCategoryId == null ? null : _addProductDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة منتج جديد'),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getProducts(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final products = snapshot.data!;
                      if (products.isEmpty) {
                        return const Center(child: Text('لا توجد منتجات في هذا المجلد'));
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final prod = products[index];
                          final qty = _cart[prod['id']] ?? 0;
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    child: const Icon(Icons.image, size: 50, color: Colors.grey),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(prod['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text('الماركة: ${prod['brand']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      Text('السعر: \$${prod['price']}', style: const TextStyle(color: Color(0xFFD4A373), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () {
                                        if (qty > 0) {
                                          setState(() {
                                            _cart[prod['id']] = qty - 1;
                                            if (_cart[prod['id']] == 0) _cart.remove(prod['id']);
                                          });
                                        }
                                      },
                                    ),
                                    Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFFD4A373)),
                                      onPressed: () {
                                        setState(() {
                                          _cart[prod['id']] = qty + 1;
                                        });
                                      },
                                    ),
                                  ],
                                )
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getCategories() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('categories', where: 'section = ?', whereArgs: [widget.section]);
  }

  Future<List<Map<String, dynamic>>> _getProducts() async {
    final db = await DatabaseHelper.instance.database;
    if (_searchQuery.isNotEmpty) {
      return await db.query(
        'products',
        where: 'name LIKE ? OR brand LIKE ?',
        whereArgs: ['%$_searchQuery%', '%$_searchQuery%'],
      );
    }
    if (_selectedCategoryId == null) return [];
    return await db.query('products', where: 'category_id = ?', whereArgs: [_selectedCategoryId]);
  }

  void _addCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مجلد جديد'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'اسم المجلد (مثلاً: لوشن)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final db = await DatabaseHelper.instance.database;
                await db.insert('categories', {'section': widget.section, 'name': controller.text});
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  void _deleteCategory(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    setState(() {
      if (_selectedCategoryId == id) _selectedCategoryId = null;
    });
  }

  void _addProductDialog() {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنتج')),
            TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'الماركة')),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty) {
                final db = await DatabaseHelper.instance.database;
                await db.insert('products', {
                  'category_id': _selectedCategoryId,
                  'name': nameCtrl.text,
                  'brand': brandCtrl.text,
                  'price': double.parse(priceCtrl.text),
                  'image_path': '',
                });
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text('إضافة'),
          )
        ],
      ),
    );
  }

  void _openCartDialog() {
    final customerCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double total = 0;
          return AlertDialog(
            title: const Text('سلة الطلبات الحالية'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: customerCtrl, decoration: const InputDecoration(labelText: 'اسم الزبون')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'قيمة الحسم \$'),
                    onChanged: (v) => setDialogState(() {}),
                  ),
                  const Divider(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send),
                    label: const Text('تأكيد وإرسال كطلب جديد'),
                    onPressed: () async {
                      if (customerCtrl.text.isNotEmpty && _cart.isNotEmpty) {
                        final db = await DatabaseHelper.instance.database;
                        double discount = double.tryParse(discountCtrl.text) ?? 0;
                        int orderId = await db.insert('orders', {
                          'customer_name': customerCtrl.text,
                          'section': widget.section,
                          'total_amount': total,
                          'discount': discount,
                          'final_amount': total - discount,
                          'status': 'pending',
                          'created_at': DateTime.now().toIso8601String(),
                        });

                        _cart.forEach((prodId, qty) async {
                          await db.insert('order_items', {
                            'order_id': orderId,
                            'product_name': 'منتج $prodId',
                            'quantity': qty,
                            'price': 10.0,
                          });
                        });

                        setState(() {
                          _cart.clear();
                        });
                        Navigator.pop(context);
                      }
                    },
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 6. ORDERS & INSTALLMENTS MANAGEMENT
// ==========================================
class OrdersManagementScreen extends StatefulWidget {
  final String section;
  const OrdersManagementScreen({Key? key, required this.section}) : super(key: key);

  @override
  _OrdersManagementScreenState createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends State<OrdersManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('إدارة الطلبات والأرشيف - ${widget.section}'),
          backgroundColor: const Color(0xFFD4A373),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'طلبات قيد التسليم'),
              Tab(text: 'الأرشيف والأقساط'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOrdersList('pending'),
            _buildOrdersList('delivered'),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(String status) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getOrders(status),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snapshot.data!;
        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text('الزبون: ${order['customer_name']}'),
                subtitle: Text('المبلغ النهائي: \$${order['final_amount']} | التاريخ: ${order['created_at'].toString().substring(0, 10)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      onPressed: () => _generatePdfAndShare(order),
                    ),
                    if (status == 'pending')
                      ElevatedButton(
                        onPressed: () => _markAsDelivered(order['id']),
                        child: const Text('تم التسليم'),
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

  Future<List<Map<String, dynamic>>> _getOrders(String status) async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('orders', where: 'section = ? AND status = ?', whereArgs: [widget.section, status]);
  }

  void _markAsDelivered(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('orders', {'status': 'delivered'}, where: 'id = ?', whereArgs: [id]);
    setState(() {});
  }

  void _generatePdfAndShare(Map<String, dynamic> order) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('فاتورة - ${order['section']}', style: const pw.TextStyle(fontSize: 24)),
              pw.SizedBox(height: 20),
              pw.Text('الزبون: ${order['customer_name']}'),
              pw.Text('المبلغ الإجمالي: \$${order['total_amount']}'),
              pw.Text('الحسم: \$${order['discount']}'),
              pw.Text('المبلغ النهائي: \$${order['final_amount']}'),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Invoice_${order['id']}.pdf');
  }
}
