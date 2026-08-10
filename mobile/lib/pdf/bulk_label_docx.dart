import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';

import '../bulk/bulk_label_models.dart';

/// Builds an editable Propak Avery 5163 `.docx` from the Word label template.
///
/// Layout (logo, italic field labels, bold values, 2×5 grid) is cloned from
/// [assets/templates/propak_avery_5163.docx] so stickers match the template.
class BulkLabelDocx {
  BulkLabelDocx._();

  static const assetPath = 'assets/templates/propak_avery_5163.docx';
  static const perSheet = 10;
  static const rows = 5;

  /// Produce a multi-page DOCX for already qty-expanded [labels].
  static Future<Uint8List> build(List<BulkLabelInstance> labels) async {
    final template = await rootBundle.load(assetPath);
    final archive = ZipDecoder().decodeBytes(template.buffer.asUint8List());
    final docEntry = archive.findFile('word/document.xml');
    if (docEntry == null) {
      throw StateError('Propak template is missing word/document.xml');
    }

    final docXml = utf8.decode(docEntry.content);
    final document = XmlDocument.parse(docXml);
    final body = _child(document.rootElement, 'body');
    final outer = body.childElements.firstWhere((e) => e.name.local == 'tbl');
    final firstRow = outer.childElements.firstWhere((e) => e.name.local == 'tr');
    final cells = firstRow.childElements
        .where((e) => e.name.local == 'tc')
        .toList(growable: false);
    if (cells.length < 3) {
      throw StateError('Propak template outer table is malformed');
    }

    final proto = cells[0].copy();
    final gutter = cells[1].copy();
    final emptyLabel = cells[2].copy();
    final sectPr = body.childElements.firstWhere((e) => e.name.local == 'sectPr');

    // Rebuild body: one Avery sheet table per page.
    body.children.clear();
    final pages = <List<BulkLabelInstance>>[];
    for (var i = 0; i < labels.length; i += perSheet) {
      final end = (i + perSheet < labels.length) ? i + perSheet : labels.length;
      pages.add(labels.sublist(i, end));
    }
    if (pages.isEmpty) {
      pages.add(const []);
    }

    for (var pi = 0; pi < pages.length; pi++) {
      if (pi > 0) {
        body.children.add(_pageBreakParagraph());
      }
      body.children.add(
        _makeSheet(
          templateOuter: outer,
          proto: proto,
          gutter: gutter,
          emptyLabel: emptyLabel,
          chunk: pages[pi],
          picBase: 1000 + pi * 20,
        ),
      );
    }
    body.children.add(_w('p'));
    body.children.add(sectPr.copy());

    final outXml = document.toXmlString(pretty: false);
    final out = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'word/document.xml') {
        out.addFile(ArchiveFile.string(file.name, outXml));
      } else {
        out.addFile(ArchiveFile.bytes(file.name, file.content));
      }
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(out));
  }

  static XmlElement _makeSheet({
    required XmlElement templateOuter,
    required XmlElement proto,
    required XmlElement gutter,
    required XmlElement emptyLabel,
    required List<BulkLabelInstance> chunk,
    required int picBase,
  }) {
    final tbl = templateOuter.copy();
    // Drop existing rows; keep tblPr / tblGrid.
    final keep = tbl.childElements
        .where((e) => e.name.local == 'tblPr' || e.name.local == 'tblGrid')
        .map((e) => e.copy())
        .toList();
    tbl.children
      ..clear()
      ..addAll(keep);

    var idx = 0;
    for (var r = 0; r < rows; r++) {
      final tr = _w('tr', children: [
        _w('trPr', children: [
          _w('cantSplit'),
          _w(
            'trHeight',
            attributes: {
              'w:hRule': 'exact',
              'w:val': '2880',
            },
          ),
        ]),
      ]);
      for (final c in [0, 1, 2]) {
        if (c == 1) {
          tr.children.add(gutter.copy());
        } else if (idx < chunk.length) {
          final cell = _fillCell(
            proto.copy(),
            chunk[idx],
            picId: picBase + idx,
          );
          tr.children.add(cell);
          idx++;
        } else {
          tr.children.add(emptyLabel.copy());
        }
      }
      tbl.children.add(tr);
    }
    return tbl;
  }

  static XmlElement _fillCell(
    XmlElement cell,
    BulkLabelInstance label, {
    required int picId,
  }) {
    final nested = cell.childElements.firstWhere((e) => e.name.local == 'tbl');
    final fieldRows = nested.childElements
        .where((e) => e.name.local == 'tr')
        .toList(growable: false);
    if (fieldRows.length < 3) {
      throw StateError('Propak nested field table is malformed');
    }

    void setValue(XmlElement row, String value) {
      final tcs = row.childElements
          .where((e) => e.name.local == 'tc')
          .toList(growable: false);
      final p = tcs[1].childElements.firstWhere((e) => e.name.local == 'p');
      _setRunText(p, value, bold: true);
    }

    void setIdLabel(XmlElement row, String idLabel) {
      final tcs = row.childElements
          .where((e) => e.name.local == 'tc')
          .toList(growable: false);
      final p = tcs[0].childElements.firstWhere((e) => e.name.local == 'p');
      _setRunText(p, idLabel, italic: true);
    }

    setValue(fieldRows[0], label.poNumber);
    setValue(fieldRows[1], label.cpo);
    setIdLabel(fieldRows[2], label.idFieldLabel);
    setValue(fieldRows[2], label.tagOrPart);

    for (final el in cell.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'docPr') {
        el.setAttribute('id', '$picId');
        el.setAttribute('name', 'Picture $picId');
      }
    }
    return cell;
  }

  static void _setRunText(
    XmlElement paragraph,
    String text, {
    bool bold = false,
    bool italic = false,
  }) {
    // Keep pPr; replace runs.
    final keep = paragraph.childElements
        .where((e) => e.name.local == 'pPr')
        .map((e) => e.copy())
        .toList();
    paragraph.children
      ..clear()
      ..addAll(keep);

    final rPrChildren = <XmlNode>[];
    if (italic) {
      rPrChildren.add(_w('i'));
      rPrChildren.add(_w('iCs'));
    }
    if (bold) {
      rPrChildren.add(_w('b'));
      rPrChildren.add(_w('bCs'));
    }
    rPrChildren.add(_w('sz', attributes: {'w:val': '28'}));
    rPrChildren.add(_w('szCs', attributes: {'w:val': '28'}));

    final tAttrs = <XmlAttribute>[];
    if (text.isNotEmpty &&
        (text.startsWith(' ') || text.endsWith(' ') || text.contains('\t'))) {
      tAttrs.add(
        XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve'),
      );
    }

    paragraph.children.add(
      _w('r', children: [
        _w('rPr', children: rPrChildren),
        XmlElement(
          XmlName.parts('t', prefix: 'w'),
          tAttrs,
          [XmlText(text)],
        ),
      ]),
    );
  }

  static XmlElement _pageBreakParagraph() {
    return _w('p', children: [
      _w('r', children: [
        _w('br', attributes: {'w:type': 'page'}),
      ]),
    ]);
  }

  static XmlElement _child(XmlElement parent, String local) {
    return parent.childElements.firstWhere((e) => e.name.local == local);
  }

  static XmlElement _w(
    String local, {
    Map<String, String> attributes = const {},
    List<XmlNode> children = const [],
  }) {
    return XmlElement(
      XmlName.parts(local, prefix: 'w'),
      [
        for (final e in attributes.entries)
          XmlAttribute(XmlName.qualified(e.key), e.value),
      ],
      children,
    );
  }
}
