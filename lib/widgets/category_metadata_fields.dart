import 'package:flutter/material.dart';
import '../models/card_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/lego_build_kind.dart';
import '../models/collection_category.dart';

/// Formulaire des champs spécifiques par catégorie (stockés dans `metadata`).
class CategoryMetadataFields extends StatefulWidget {
  final CollectionCategory category;
  final CardSubcategory? initialCardSubcategory;
  final MediaFormat? initialMediaFormat;
  final LegoBuildKind? initialLegoKind;
  final bool lockCardSubcategory;
  final bool lockMediaFormat;
  final bool lockLegoKind;

  const CategoryMetadataFields({
    super.key,
    required this.category,
    this.initialCardSubcategory,
    this.initialMediaFormat,
    this.initialLegoKind,
    this.lockCardSubcategory = false,
    this.lockMediaFormat = false,
    this.lockLegoKind = false,
  });

  @override
  State<CategoryMetadataFields> createState() => CategoryMetadataFieldsState();
}

class CategoryMetadataFieldsState extends State<CategoryMetadataFields> {
  // Cartes
  late CardSubcategory _cardType =
      widget.initialCardSubcategory ?? CardSubcategory.pokemon;
  CardCondition _condition = CardCondition.nearMint;
  bool _isGraded = false;
  GradingCompany _gradingCompany = GradingCompany.psa;
  final _gradeController = TextEditingController();

  // Voiture
  final _mileageController = TextEditingController();
  final _maintenanceController = TextEditingController();
  final _logbookController = TextEditingController();

  // Timbres / monnaies
  final _countryController = TextEditingController();
  final _mintController = TextEditingController();
  final _rarityController = TextEditingController();

  // Média
  late MediaFormat _mediaFormat =
      widget.initialMediaFormat ?? MediaFormat.vinyl;
  final _discColorController = TextEditingController();
  bool _limitedEdition = false;
  PressingType _pressing = PressingType.original;
  final _barcodeController = TextEditingController();

  // Lego
  late LegoBuildKind _legoKind =
      widget.initialLegoKind ?? LegoBuildKind.lego;
  final _setNumberController = TextEditingController();
  final _pieceCountController = TextEditingController();
  bool _isBuilt = false;
  bool _boxIncluded = true;

  // Montres
  final _watchBrandController = TextEditingController();
  final _watchModelController = TextEditingController();
  final _watchRefController = TextEditingController();
  final _watchYearController = TextEditingController();

  // Jeux vidéo
  final _gamePlatformController = TextEditingController();
  final _gameYearController = TextEditingController();

  // Films
  final _movieYearController = TextEditingController();
  final _movieDirectorController = TextEditingController();
  String _movieKind = 'movie';

  @override
  void dispose() {
    _gradeController.dispose();
    _mileageController.dispose();
    _maintenanceController.dispose();
    _logbookController.dispose();
    _countryController.dispose();
    _mintController.dispose();
    _rarityController.dispose();
    _discColorController.dispose();
    _barcodeController.dispose();
    _setNumberController.dispose();
    _pieceCountController.dispose();
    _watchBrandController.dispose();
    _watchModelController.dispose();
    _watchRefController.dispose();
    _watchYearController.dispose();
    _gamePlatformController.dispose();
    _gameYearController.dispose();
    _movieYearController.dispose();
    _movieDirectorController.dispose();
    super.dispose();
  }

  String? get subcategory {
    if (widget.category == CollectionCategory.card) return _cardType.dbValue;
    return null;
  }

  Map<String, dynamic> buildMetadata() {
    switch (widget.category) {
      case CollectionCategory.card:
        return {
          'condition': _condition.dbValue,
          'is_graded': _isGraded,
          if (_isGraded) ...{
            'grading_company': _gradingCompany.dbValue,
            'grade': _gradeController.text.trim(),
          },
        };
      case CollectionCategory.car:
        return {
          if (_mileageController.text.trim().isNotEmpty)
            'mileage_km': int.tryParse(_mileageController.text.trim()),
          if (_maintenanceController.text.trim().isNotEmpty)
            'maintenance_history': _maintenanceController.text.trim(),
          if (_logbookController.text.trim().isNotEmpty)
            'logbook': _logbookController.text.trim(),
        };
      case CollectionCategory.stamp:
      case CollectionCategory.coin:
        return {
          if (_countryController.text.trim().isNotEmpty)
            'country': _countryController.text.trim(),
          if (_mintController.text.trim().isNotEmpty)
            'mint': _mintController.text.trim(),
          if (_rarityController.text.trim().isNotEmpty)
            'rarity_tirage': _rarityController.text.trim(),
        };
      case CollectionCategory.media:
        return {
          'format': _mediaFormat.dbValue,
          if (_discColorController.text.trim().isNotEmpty)
            'disc_color': _discColorController.text.trim(),
          'limited_edition': _limitedEdition,
          'pressing': _pressing.dbValue,
          if (_barcodeController.text.trim().isNotEmpty)
            'barcode': _barcodeController.text.trim(),
        };
      case CollectionCategory.lego:
        return {
          'lego_kind': _legoKind.dbValue,
          if (_setNumberController.text.trim().isNotEmpty)
            'set_number': _setNumberController.text.trim(),
          if (_pieceCountController.text.trim().isNotEmpty)
            'piece_count': int.tryParse(_pieceCountController.text.trim()),
          'is_built': _isBuilt,
          'box_included': _boxIncluded,
        };
      case CollectionCategory.watch:
        return {
          if (_watchBrandController.text.trim().isNotEmpty)
            'brand': _watchBrandController.text.trim(),
          if (_watchModelController.text.trim().isNotEmpty)
            'model': _watchModelController.text.trim(),
          if (_watchRefController.text.trim().isNotEmpty)
            'reference': _watchRefController.text.trim(),
          if (_watchYearController.text.trim().isNotEmpty)
            'year': _watchYearController.text.trim(),
        };
      case CollectionCategory.videogame:
        return {
          if (_gamePlatformController.text.trim().isNotEmpty)
            'platform': _gamePlatformController.text.trim(),
          if (_gameYearController.text.trim().isNotEmpty)
            'year': _gameYearController.text.trim(),
        };
      case CollectionCategory.movie:
        return {
          'media_kind': _movieKind,
          if (_movieYearController.text.trim().isNotEmpty)
            'year': _movieYearController.text.trim(),
          if (_movieDirectorController.text.trim().isNotEmpty)
            'director': _movieDirectorController.text.trim(),
        };
      default:
        return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (widget.category) {
        CollectionCategory.card => _cardFields(),
        CollectionCategory.car => _carFields(),
        CollectionCategory.stamp || CollectionCategory.coin => _numismaticFields(),
        CollectionCategory.media => _mediaFields(),
        CollectionCategory.lego => _legoFields(),
        CollectionCategory.watch => _watchFields(),
        CollectionCategory.videogame => _gameFields(),
        CollectionCategory.movie => _movieFields(),
        _ => const [],
      },
    );
  }

  List<Widget> _cardFields() => [
        if (widget.lockCardSubcategory)
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Univers'),
            child: Text(_cardType.label),
          )
        else
          DropdownButtonFormField<CardSubcategory>(
            initialValue: _cardType,
            decoration: const InputDecoration(labelText: 'Univers / série'),
            items: CardSubcategory.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (v) => setState(() => _cardType = v ?? _cardType),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CardCondition>(
          initialValue: _condition,
          decoration: const InputDecoration(labelText: 'État'),
          items: CardCondition.values
              .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
              .toList(),
          onChanged: (v) => setState(() => _condition = v ?? _condition),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Carte gradée'),
          value: _isGraded,
          onChanged: (v) => setState(() => _isGraded = v),
        ),
        if (_isGraded) ...[
          DropdownButtonFormField<GradingCompany>(
            initialValue: _gradingCompany,
            decoration: const InputDecoration(labelText: 'Société'),
            items: GradingCompany.values
                .map((g) => DropdownMenuItem(value: g, child: Text(g.label)))
                .toList(),
            onChanged: (v) => setState(() => _gradingCompany = v ?? _gradingCompany),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gradeController,
            decoration: const InputDecoration(
              labelText: 'Note (ex: 10, 9.5)',
            ),
          ),
        ],
      ];

  List<Widget> _carFields() => [
        TextField(
          controller: _mileageController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kilométrage (km)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _maintenanceController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Historique d\'entretien',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _logbookController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Carnet de bord'),
        ),
      ];

  List<Widget> _numismaticFields() => [
        TextField(
          controller: _countryController,
          decoration: const InputDecoration(labelText: 'Pays d\'origine'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mintController,
          decoration: const InputDecoration(labelText: 'Atelier de frappe'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rarityController,
          decoration: const InputDecoration(
            labelText: 'Rareté / tirage',
            hintText: 'ex: 500 exemplaires',
          ),
        ),
      ];

  List<Widget> _mediaFields() => [
        if (widget.lockMediaFormat)
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Format'),
            child: Text(_mediaFormat.label),
          )
        else
          DropdownButtonFormField<MediaFormat>(
            initialValue: _mediaFormat,
            decoration: const InputDecoration(labelText: 'Format'),
            items: MediaFormat.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (v) => setState(() => _mediaFormat = v ?? _mediaFormat),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _discColorController,
          decoration: const InputDecoration(
            labelText: 'Couleur du disque',
            hintText: 'ex: Noir, Vinyle coloré',
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Édition limitée'),
          value: _limitedEdition,
          onChanged: (v) => setState(() => _limitedEdition = v),
        ),
        DropdownButtonFormField<PressingType>(
          initialValue: _pressing,
          decoration: const InputDecoration(labelText: 'Pressage'),
          items: PressingType.values
              .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
          onChanged: (v) => setState(() => _pressing = v ?? _pressing),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _barcodeController,
          decoration: const InputDecoration(
            labelText: 'Code-barres / QR (manuel)',
            hintText: 'Scan QR : bientôt disponible',
          ),
        ),
        TextButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scan QR : prévu dans une prochaine version'),
              ),
            );
          },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scanner un QR code'),
        ),
      ];

  List<Widget> _legoFields() => [
        if (widget.lockLegoKind)
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Type'),
            child: Text(_legoKind.label),
          )
        else
          DropdownButtonFormField<LegoBuildKind>(
            initialValue: _legoKind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: LegoBuildKind.values
                .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                .toList(),
            onChanged: (v) => setState(() => _legoKind = v ?? _legoKind),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _setNumberController,
          decoration: const InputDecoration(labelText: 'N° de set'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pieceCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nombre de pièces'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Modèle monté'),
          value: _isBuilt,
          onChanged: (v) => setState(() => _isBuilt = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Boîte d\'origine'),
          value: _boxIncluded,
          onChanged: (v) => setState(() => _boxIncluded = v),
        ),
      ];

  List<Widget> _watchFields() => [
        TextField(
          controller: _watchBrandController,
          decoration: const InputDecoration(labelText: 'Marque'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _watchModelController,
          decoration: const InputDecoration(labelText: 'Modèle'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _watchRefController,
          decoration: const InputDecoration(labelText: 'Référence'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _watchYearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Année'),
        ),
      ];

  List<Widget> _gameFields() => [
        TextField(
          controller: _gamePlatformController,
          decoration: const InputDecoration(
            labelText: 'Plateforme',
            hintText: 'PS5, Switch, PC…',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _gameYearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Année de sortie'),
        ),
      ];

  List<Widget> _movieFields() => [
        DropdownButtonFormField<String>(
          initialValue: _movieKind,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'movie', child: Text('Film')),
            DropdownMenuItem(value: 'series', child: Text('Série')),
          ],
          onChanged: (v) => setState(() => _movieKind = v ?? 'movie'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _movieYearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Année'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _movieDirectorController,
          decoration: const InputDecoration(labelText: 'Réalisateur / créateur'),
        ),
      ];
}
