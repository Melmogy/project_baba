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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام الرواتب والضرائب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), 
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Tahoma', 
      ),
      home: const HomeScreen(),
    );
  }
}

// ================= النماذج (Models) =================

class DeductionItem {
  final String title;
  final double amount;
  DeductionItem({required this.title, required this.amount});
}

class EmployeeReport {
  final String code;
  final String name;
  final double totalIncome;
  final List<DeductionItem> deductions;

  EmployeeReport({
    required this.code,
    required this.name,
    required this.totalIncome,
    required this.deductions,
  });

  double get totalDeductions =>
      deductions.fold(0, (sum, item) => sum + item.amount);

  double get netIncome => totalIncome - totalDeductions;
}

// ================= واجهة المستخدم (UI) =================

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<EmployeeReport> _employees = [];
  bool _isLoading = false;

  double _safeParse(dynamic value) {
    if (value == null) return 0.0;
    String cleanString = value.toString().replaceAll(',', '').replaceAll(' ', '').trim();
    return double.tryParse(cleanString) ?? 0.0;
  }

  Future<void> _processExcel() async {
    setState(() {
      _isLoading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        var bytes = File(result.files.single.path!).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        List<EmployeeReport> tempEmployees = [];

        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table]!;
          
          int colTotal = 1;
          int colInsurance = -1;
          int colJoined = -1;
          int colUnjoined = -1;
          int colFellowship = -1;
          int colSocial = -1; 

          if (sheet.maxRows > 1) {
            var headerRow = sheet.row(1); 
            for (int j = 0; j < headerRow.length; j++) {
              if (headerRow[j] == null || headerRow[j]?.value == null) continue;
              
              String headerText = headerRow[j]!.value.toString().replaceAll('ـ', '').trim(); 
              
              if (headerText.contains('اجمالي الاستحقاقات') || headerText.contains('الاستحقاقات')) colTotal = j;
              else if (headerText.contains('التأمينات') || headerText.contains('تأمينات')) colInsurance = j;
              else if (headerText.contains('غير المنضمة') || headerText.contains('الغير المنضمة')) colUnjoined = j;
              else if (headerText.contains('المنضمة') && !headerText.contains('غير')) colJoined = j;
              else if (headerText.contains('زمالة') || headerText.contains('الزمالة')) colFellowship = j;
              else if (headerText.contains('الإجتماعية') || headerText.contains('الاجتماعية')) colSocial = j;
            }
          }

          for (int i = 3; i < sheet.maxRows; i++) {
            var row = sheet.row(i);
            
            if (row.isEmpty || row.length <= colTotal) continue;
            if (row[0] == null || row[0]?.value == null) continue;

            String name = row[0]!.value.toString().trim();
            if (name.isEmpty) continue;
            
            double totalIncome = _safeParse(row[colTotal]?.value);
            List<DeductionItem> currentDeductions = [];

            if (colInsurance != -1 && colInsurance < row.length) {
              double ins = _safeParse(row[colInsurance]?.value);
              if (ins > 0) currentDeductions.add(DeductionItem(title: 'تأمينات اجتماعية', amount: ins));
            }

            if (colJoined != -1 && colJoined < row.length) {
              double joined = _safeParse(row[colJoined]?.value);
              if (joined > 0) currentDeductions.add(DeductionItem(title: 'علاوات منضمة', amount: joined));
            }

            if (colUnjoined != -1 && colUnjoined < row.length) {
              double unjoined = _safeParse(row[colUnjoined]?.value);
              if (unjoined > 0) currentDeductions.add(DeductionItem(title: 'علاوات غير منضمة', amount: unjoined));
            }

            if (colFellowship != -1 && colFellowship < row.length) {
              double fellowship = _safeParse(row[colFellowship]?.value);
              if (fellowship > 0) currentDeductions.add(DeductionItem(title: 'زمالة المعلمين', amount: fellowship));
            }

            if (colSocial != -1 && colSocial < row.length) {
              double social = _safeParse(row[colSocial]?.value);
              if (social > 0) currentDeductions.add(DeductionItem(title: 'علاوات اجتماعية', amount: social));
            }

            if (totalIncome == 0 && currentDeductions.isEmpty) continue;

            tempEmployees.add(
              EmployeeReport(
                code: 'EMP-${(i - 2).toString().padLeft(3, '0')}',
                name: name,
                totalIncome: totalIncome,
                deductions: currentDeductions,
              ),
            );
          }
        }

        setState(() {
          _employees = tempEmployees;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت معالجة البيانات بنجاح!', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء القراءة. تأكد من تنسيق الملف.', textDirection: TextDirection.rtl)),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('نظام التقارير المالية', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'مدارس هيئة قناة السويس ببورتوفيق\nقم برفع ملف الإكسيل (xlsx.) لاستخراج التقارير',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _processExcel,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.upload_file, size: 28),
                    label: const Text('اختيار ومعالجة الملف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            Expanded(
              child: _employees.isEmpty
                  ? const Center(
                      child: Text('لا توجد بيانات، قم برفع الملف للبدء', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      itemCount: _employees.length,
                      itemBuilder: (context, index) {
                        final emp = _employees[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 15),
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(15),
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Text(emp.code.split('-').last, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                            ),
                            title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text('الصافي: ${emp.netIncome.toStringAsFixed(2)} جنيه'),
                            trailing: IconButton(
                              icon: const Icon(Icons.print, color: Colors.teal),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PdfPreviewScreen(
                                      employees: [emp],
                                      // التعديل هنا: نمرر اسم الموظف ليكون اسم الملف
                                      fileName: 'تقرير_${emp.name.replaceAll(' ', '_')}', 
                                    ), 
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _employees.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfPreviewScreen(
                      employees: _employees,
                      // اسم الملف في حالة طباعة الكل
                      fileName: 'جميع_التقارير_مدارس_القناة', 
                    ), 
                  ),
                );
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('طباعة الكل'),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}

// ================= قسم الـ PDF والطباعة =================

class PdfPreviewScreen extends StatelessWidget {
  final List<EmployeeReport> employees;
  final String fileName; // المتغير الجديد لاسم الملف

  const PdfPreviewScreen({
    Key? key, 
    required this.employees, 
    required this.fileName, // نطلبه هنا
  }) : super(key: key);

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicFontBold = await PdfGoogleFonts.cairoBold();

    for (var employee in employees) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(
            base: arabicFont, 
            bold: arabicFontBold,
            fontFallback: [arabicFont] 
          ),
          build: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(child: pw.Text('مدارس هيئة قناة السويس ببورتوفيق', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700))),
                  pw.SizedBox(height: 10),
                  pw.Center(child: pw.Text('مفردات مرتب (تقرير مالي)', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 30),
                  
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الاسم: ${employee.name}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text('كود: ${employee.code}', style: const pw.TextStyle(fontSize: 18)),
                    ]
                  ),
                  pw.Divider(thickness: 2),
                  pw.SizedBox(height: 20),

                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    color: PdfColors.grey200,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('إجمالي الاستحقاقات:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${employee.totalIncome.toStringAsFixed(2)} جنيه', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  if (employee.deductions.isNotEmpty) ...[
                    pw.Text('الخصومات والاستقطاعات:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    pw.Table.fromTextArray(
                      headers: ['البند', 'المبلغ'],
                      data: employee.deductions.map((d) => [d.title, d.amount.toStringAsFixed(2)]).toList(),
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      cellAlignment: pw.Alignment.centerRight,
                      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('إجمالي الخصم: ${employee.totalDeductions.toStringAsFixed(2)} جنيه', style: pw.TextStyle(fontSize: 14, color: PdfColors.red800, fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                    pw.Divider(),
                    pw.SizedBox(height: 20),
                  ],

                  pw.Container(
                    padding: const pw.EdgeInsets.all(15),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green100,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('صافي الدخل النهائي:', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${employee.netIncome.toStringAsFixed(2)} جنيه', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      ]
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName.replaceAll('_', ' ')), // عرض الاسم في شريط العنوان من فوق
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName: '$fileName.pdf', // التعديل الأهم: إجبار نافذة الحفظ على استخدام هذا الاسم
      ),
    );
  }
}