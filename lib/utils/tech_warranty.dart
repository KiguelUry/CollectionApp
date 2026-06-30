import 'package:flutter/material.dart';

enum TechWarrantyStatus { unknown, valid, soon, expired }

TechWarrantyStatus warrantyStatus(String? isoDate) {
  if (isoDate == null || isoDate.trim().isEmpty) {
    return TechWarrantyStatus.unknown;
  }
  final end = DateTime.tryParse(isoDate.trim());
  if (end == null) return TechWarrantyStatus.unknown;
  final today = DateTime.now();
  final endDay = DateTime(end.year, end.month, end.day);
  final nowDay = DateTime(today.year, today.month, today.day);
  if (endDay.isBefore(nowDay)) return TechWarrantyStatus.expired;
  if (!endDay.isAfter(nowDay.add(const Duration(days: 30)))) {
    return TechWarrantyStatus.soon;
  }
  return TechWarrantyStatus.valid;
}

String? warrantySubtitle(String? isoDate) {
  final status = warrantyStatus(isoDate);
  final end = DateTime.tryParse(isoDate?.trim() ?? '');
  if (end == null) return null;
  final label =
      '${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}/${end.year}';
  return switch (status) {
    TechWarrantyStatus.expired => 'Garantie expirée ($label)',
    TechWarrantyStatus.soon => 'Garantie bientôt finie ($label)',
    TechWarrantyStatus.valid => 'Garantie jusqu\'au $label',
    TechWarrantyStatus.unknown => null,
  };
}

Color warrantyAccentColor(TechWarrantyStatus status) {
  return switch (status) {
    TechWarrantyStatus.expired => Colors.red.shade700,
    TechWarrantyStatus.soon => Colors.orange.shade800,
    TechWarrantyStatus.valid => Colors.green.shade700,
    TechWarrantyStatus.unknown => Colors.grey,
  };
}
