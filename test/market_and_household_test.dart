import 'package:collection_app/services/boardgame_market_service.dart';
import 'package:collection_app/services/household_service.dart';
import 'package:collection_app/utils/holder_label_utils.dart';
import 'package:collection_app/utils/pantheon_ranking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('les offres sous 45 % de la médiane sont écartées', () {
    final summary = BoardgameMarketService.summarizePositivePrices(
      [3, 3, 12, 15, 16],
    );
    expect(summary, isNotNull);
    expect(summary!.min, 12);
    expect(summary.max, 16);
    expect(summary.secondhand, greaterThan(8));
    expect(summary.secondhand, lessThan(12));
  });

  test('l\'occasion vaut environ 65 % de la médiane neuve', () {
    final summary = BoardgameMarketService.summarizePositivePrices(
      [20, 22, 24],
    );
    expect(summary!.median, 22);
    expect(summary.secondhand, 14.3);
  });

  test('Annecy est un lieu quand on choisit Lieu', () {
    expect(
      formatManualHolderLabel('Annecy', kind: ManualHolderKind.place),
      'À Annecy',
    );
    expect(
      formatManualHolderLabel('Annecy', kind: ManualHolderKind.person),
      'Chez Annecy',
    );
    expect(
      formatManualHolderLabel('Chez Annecy', kind: ManualHolderKind.place),
      'À Annecy',
    );
  });

  test('un foyer regroupe le lieu et ses habitants', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await HouseholdService.instance.save(const [
      Household(
        id: 'home-1',
        place: 'Braine-l\'Alleud',
        people: ['Papa', 'Mom'],
      ),
    ]);
    final papa = HouseholdService.instance.matchLabel('Chez Papa');
    final place = HouseholdService.instance.matchLabel('À Braine-l\'Alleud');
    final mom = HouseholdService.instance.matchLabel('Chez Mom');
    expect(papa?.id, 'home-1');
    expect(place?.id, 'home-1');
    expect(mom?.id, 'home-1');
    expect(HouseholdService.instance.displayFor(papa!), 'À Braine-l\'Alleud');
  });

  test('les liens boutiques pointent vers des recherches réelles', () {
    final casedepart = BoardgameMarketService.caseDepartSearchUrl('Pandemic');
    expect(casedepart, contains('google.com/search'));
    expect(casedepart, contains('casedepart.be'));
    expect(casedepart, isNot(contains('btnI')));
    expect(casedepart, isNot(contains('controller=search')));

    final zebre = BoardgameMarketService.zebreAPoisSearchUrl('Sea Salt & Paper');
    expect(zebre, contains('leoproductsearch'));
    expect(zebre, contains('search_query=Sea+Salt+Paper'));

    expect(
      BoardgameMarketService.okkazeoSearchUrl('Catan'),
      'https://www.okkazeo.com/jeux/resultats?rech_nom=Catan',
    );
  });

  test('le top automatique ignore extensions et doublons', () {
    final ids = pickAutoPantheonIds(const [
      PantheonCandidate(id: 'a', title: '7 Wonders', rating: 9),
      PantheonCandidate(
        id: 'b',
        title: '7 Wonders: Armada',
        isExpansion: true,
        rating: 10,
      ),
      PantheonCandidate(
        id: 'c',
        title: '7 Wonders: Architects',
        bggId: '12',
        rating: 8,
      ),
      PantheonCandidate(
        id: 'd',
        title: '7 Wonders Architects copie',
        bggId: '12',
        rating: 6,
      ),
    ]);
    expect(ids, ['a', 'c']);
  });
}
