import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PayrollTaxApp());
}

class PayrollTaxApp extends StatelessWidget {
  const PayrollTaxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام تسوية ضرائب 2025',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003366)),
        fontFamily: 'Tahoma',
      ),
      home: const HomeScreen(),
    );
  }
}

// ================= النموذج المحاسبي وتفريغ الشرائح =================

class EmployeeData {
  final String name;
  final double totalIncome;    
  final double insurance;      
  final double joinedAllow;    
  final double unjoinedAllow;  
  final double socialAllow;    
  final double fellowship;     
  final double alreadyPaidTax; 

  EmployeeData({
    required this.name,
    required this.totalIncome,
    required this.insurance,
    required this.joinedAllow,
    required this.unjoinedAllow,
    required this.socialAllow,
    required this.fellowship,
    required this.alreadyPaidTax,
  });

  // ===== الجدول الأول =====
  double get totalDeductions => insurance + joinedAllow + unjoinedAllow + socialAllow + fellowship;
  double get netIncome => totalIncome - totalDeductions;

  // ===== الجدول الثاني (تفريغ الشرائح) =====
  double get personalExemption => 20000.0;
  double get zeroBracket => 40000.0;

  double get netIncomeAfterPersonal {
    double val = netIncome - personalExemption;
    return val > 0 ? val : 0.0;
  }

  // المتبقي
  double get remainingAfterZero {
    double val = netIncomeAfterPersonal - zeroBracket;
    return val > 0 ? val : 0.0;
  }

  // الشريحة 10% (من 1 لـ 15000)
  double get bracket10Amount => remainingAfterZero > 15000 ? 15000 : remainingAfterZero;
  double get bracket10Tax => bracket10Amount * 0.10;

  // الشريحة 15% (من 15001 لـ 30000)
  double get remainingAfter10 => remainingAfterZero - bracket10Amount;
  double get bracket15Amount => remainingAfter10 > 15000 ? 15000 : remainingAfter10;
  double get bracket15Tax => bracket15Amount * 0.15;

  // الشريحة 20% (من 30001 لـ 160000) 
  double get remainingAfter15 => remainingAfter10 - bracket15Amount;
  double get bracket20Amount => remainingAfter15 > 130000 ? 130000 : remainingAfter15;
  double get bracket20Tax => bracket20Amount * 0.20;

  // الشريحة 22.5% (من 160001 لـ 360000)
  double get remainingAfter20 => remainingAfter15 - bracket20Amount;
  double get bracket225Amount => remainingAfter20 > 200000 ? 200000 : remainingAfter20;
  double get bracket225Tax => bracket225Amount * 0.225;

  // الشريحة 25% (من 360001 لـ 1160000)
  double get remainingAfter225 => remainingAfter20 - bracket225Amount;
  double get bracket25Amount => remainingAfter225 > 800000 ? 800000 : remainingAfter225;
  double get bracket25Tax => bracket25Amount * 0.25;

  // الشريحة 27.5% (ما زاد عن ذلك)
  double get remainingAfter25 => remainingAfter225 - bracket25Amount;
  double get bracket275Amount => remainingAfter25;
  double get bracket275Tax => bracket275Amount * 0.275;

  // مجموع الضريبة المستحقة
  double get calculatedTax => bracket10Tax + bracket15Tax + bracket20Tax + bracket225Tax + bracket25Tax + bracket275Tax;

  // ====== التعديل الجديد (ناتج التسوية الضريبية) ======
  double get taxDifference => calculatedTax - alreadyPaidTax;

  // النص الديناميكي بناءً على حالة التسوية
  String get finalStatusLabel {
    if (taxDifference < 0) {
      return 'يصرف له هذا المبلغ';
    } else if (taxDifference > 0) {
      return 'يُحصّل منه هذا المبلغ';
    } else {
      return 'تسوية صفرية (ليس له أو عليه)';
    }
  }
}

// ================= الواجهة وقراءة الإكسيل =================

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<EmployeeData> _employees = [];
  bool _isLoading = false;

  double _parseRaw(Data? cell) {
    if (cell == null || cell.value == null) return 0.0;
    
    if (cell.value is double) return cell.value as double;
    if (cell.value is int) return (cell.value as int).toDouble();
    
    String s = cell.value.toString();
    if (s.contains('Formula') || s.contains('SUM') || s.startsWith('=')) return 0.0;
    
    s = s.replaceAll(',', '').replaceAll(' ', '').trim();
    RegExp regExp = RegExp(r'[-+]?[0-9]*\.?[0-9]+');
    var match = regExp.firstMatch(s);
    if (match != null) {
      return double.tryParse(match.group(0)!) ?? 0.0;
    }
    return 0.0;
  }

  double _sumCols(List<Data?> row, List<int> cols) {
    double sum = 0.0;
    for (int c in cols) {
      if (c < row.length) {
        sum += _parseRaw(row[c]);
      }
    }
    return sum;
  }

  Future<void> _pickExcel() async {
    setState(() => _isLoading = true);
    try {
      FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      
      if (res != null) {
        String filePath = res.files.single.path!;
        
        if (filePath.toLowerCase().endsWith('.xls')) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('برجاء تحويل الملف إلى xlsx أولاً!', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ));
          setState(() => _isLoading = false);
          return;
        }

        var bytes = File(filePath).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        List<EmployeeData> temp = [];

        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table]!;
          
          List<int> incCols = List.generate(16, (i) => i + 1);      
          List<int> insCols = List.generate(16, (i) => i + 19);     
          List<int> joinCols = List.generate(12, (i) => i + 37);    
          List<int> unjCols = List.generate(12, (i) => i + 51);     
          List<int> socCols = List.generate(12, (i) => i + 65);     
          List<int> felCols = List.generate(14, (i) => i + 79);     
          List<int> paidCols = List.generate(16, (i) => i + 105);   

          for (int i = 3; i < sheet.maxRows; i++) {
            var r = sheet.row(i);
            if (r.isEmpty || r.length == 0 || r[0] == null) continue;
            
            String employeeName = r[0]!.value.toString().trim();
            if (employeeName.isEmpty || employeeName == 'null' || employeeName.contains('جملة') || employeeName.contains('اجمالي')) continue;

            temp.add(EmployeeData(
              name: employeeName,
              totalIncome: _sumCols(r, incCols),
              insurance: _sumCols(r, insCols),
              joinedAllow: _sumCols(r, joinCols),
              unjoinedAllow: _sumCols(r, unjCols),
              socialAllow: _sumCols(r, socCols),
              fellowship: _sumCols(r, felCols),
              alreadyPaidTax: _sumCols(r, paidCols),
            ));
          }
        }
        setState(() => _employees = temp);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تجميع وحساب البيانات بنجاح!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ. تأكد من رفع ملف بصيغة xlsx'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('نظام التسوية الضريبية - 2025', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF003366), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF003366),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickExcel,
                icon: const Icon(Icons.upload_file),
                label: const Text('رفع ملف الإكسيل (xlsx فقط)', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
            ),
            Expanded(
              child: _employees.isEmpty 
              ? const Center(child: Text('يرجى حفظ ملفك بصيغة xlsx ثم رفعه هنا'))
              : ListView.builder(
                  itemCount: _employees.length,
                  itemBuilder: (ctx, idx) {
                    final emp = _employees[idx];
                    // تحديد اللون بناءً على حالة الموظف
                    Color statusColor = emp.taxDifference < 0 ? Colors.green : (emp.taxDifference > 0 ? Colors.red : Colors.grey);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      child: ListTile(
                        title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${emp.finalStatusLabel}: ${emp.taxDifference.abs().toStringAsFixed(2)} ج.م', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (c) => ReportPreview(e: emp))),
                      ),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= تصميم الـ PDF (التقرير الاحترافي المزدوج) =================

class ReportPreview extends StatelessWidget {
  final EmployeeData e;
  const ReportPreview({Key? key, required this.e}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تقرير: ${e.name}')),
      body: PdfPreview(
        build: (format) async {
          final pdf = pw.Document();
          final fontBold = await PdfGoogleFonts.cairoBold();
          final fontRegular = await PdfGoogleFonts.cairoRegular();

          pdf.addPage(pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
            build: (ctx) => [
              pw.Center(child: pw.Text('مدارس هيئة قناة السويس ببورتوفيق', style: const pw.TextStyle(fontSize: 14))),
              pw.Center(child: pw.Text('تقرير التسوية الضريبية السنوية للموظف - 2025', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Text('الاسم / ${e.name}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Divider(thickness: 2),

              // ================= الجدول الأول =================
              pw.Text('أولاً: بيان الاستحقاقات والخصومات للوصول إلى (صافي الدخل):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ['البيـــــــــــــــــــــــــــــــــــــــــــــــــــــــــــــان', 'القيمــــــــــــــــــــــــــــة'],
                data: [
                  ['إجمالي الاستحقاقات (جملة السنة)', e.totalIncome.toStringAsFixed(2)],
                  ['(يخصم) جملة التأمينات الاجتماعية', e.insurance.toStringAsFixed(2)],
                  ['(يخصم) جملة العلاوات المنضمة', e.joinedAllow.toStringAsFixed(2)],
                  ['(يخصم) جملة العلاوات الغير منضمة', e.unjoinedAllow.toStringAsFixed(2)],
                  ['(يخصم) جملة العلاوات الاجتماعية وزمالة المعلمين', (e.socialAllow + e.fellowship).toStringAsFixed(2)],
                  ['إجمالي الاستقطاعات المعفاة', e.totalDeductions.toStringAsFixed(2)],
                  ['صافي الدخل', e.netIncome.toStringAsFixed(2)], 
                ],
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellAlignment: pw.Alignment.centerRight,
                cellStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),

              pw.SizedBox(height: 20),

              // ================= الجدول الثاني والتعديل الأخير =================
              pw.Text('ثانياً: بيان التسوية الضريبية للوصول إلى (الفروق النهائية):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red900)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                headers: ['البيـــــــــــــــــــــــــــــــــــــــــــــــــــــــــــــان', 'القيمــــــــــــــــــــــــــــة'],
                data: [
                  ['صافي الدخل', e.netIncome.toStringAsFixed(2)],
                  ['يخصم 20000 حد الاعفاء الشخصي', '20000.00'],
                  ['يخصم 40000 شريحه معافاه', '40000.00'],
                  ['المتبقي', e.remainingAfterZero.toStringAsFixed(2)],
                  ['', ''], 
                  ['يقسم كالتالي:', ''],
                  if (e.bracket10Amount > 0)
                    ['من 1 وحتى 15000 ( ${e.bracket10Amount.toStringAsFixed(0)} ) * 10%', e.bracket10Tax.toStringAsFixed(2)],
                  if (e.bracket15Amount > 0)
                    ['من 15001 وحتى 30000 ( ${e.bracket15Amount.toStringAsFixed(0)} ) * 15%', e.bracket15Tax.toStringAsFixed(2)],
                  if (e.bracket20Amount > 0)
                    ['من 30001 وحتى 160000 (المتبقي) * 20%', e.bracket20Tax.toStringAsFixed(2)],
                  if (e.bracket225Amount > 0)
                    ['من 160001 وحتى 360000 (المتبقي) * 22.5%', e.bracket225Tax.toStringAsFixed(2)],
                  if (e.bracket25Amount > 0)
                    ['من 360001 وحتى 1160000 (المتبقي) * 25%', e.bracket25Tax.toStringAsFixed(2)],
                  if (e.bracket275Amount > 0)
                    ['ما زاد عن ذلك (المتبقي) * 27.5%', e.bracket275Tax.toStringAsFixed(2)],
                  ['', ''], 
                  ['يجمع كلا من ناتج النسب ويعطي مجموع الضريبه', e.calculatedTax.toStringAsFixed(2)],
                  ['(يخصم) الضريبة المحصلة من واقع السجلات', e.alreadyPaidTax.toStringAsFixed(2)],
                  // التعديل السحري هنا:
                  [e.finalStatusLabel, e.taxDifference.toStringAsFixed(2)], 
                ],
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
                cellAlignment: pw.Alignment.centerRight,
                cellStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),

              pw.SizedBox(height: 30),
              
              // بروزة النتيجة تحت الجدول بلون حسب الحالة
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: e.taxDifference < 0 ? PdfColors.green100 : (e.taxDifference > 0 ? PdfColors.red100 : PdfColors.grey200), 
                  border: pw.Border.all(color: e.taxDifference < 0 ? PdfColors.green900 : (e.taxDifference > 0 ? PdfColors.red900 : PdfColors.grey600))
                ),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('${e.finalStatusLabel}:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  // طباعة الرقم بالقيمة المطلقة (بدون سالب) عشان الكلمة شارحة نفسها
                  pw.Text('${e.taxDifference.abs().toStringAsFixed(2)} ج.م', style: pw.TextStyle(
                    fontSize: 16, 
                    fontWeight: pw.FontWeight.bold, 
                    color: e.taxDifference < 0 ? PdfColors.green900 : (e.taxDifference > 0 ? PdfColors.red900 : PdfColors.black)
                  )),
                ]),
              ),

              pw.SizedBox(height: 50),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                pw.Column(children: [pw.Text('المراجع المالي'), pw.SizedBox(height: 20), pw.Text('..................')]),
                pw.Column(children: [pw.Text('يعتمد، مدير المدرسة'), pw.SizedBox(height: 20), pw.Text('..................')]),
              ])
            ],
          ));
          return pdf.save();
        },
        pdfFileName: 'تقرير_${e.name.replaceAll(' ', '_')}.pdf',
      ),
    );
  }
}