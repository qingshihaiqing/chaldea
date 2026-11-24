import 'package:flutter_test/flutter_test.dart';

import 'package:chaldea/app/battle/models/battle.dart';
import 'package:chaldea/models/models.dart';

import '../../../test_init.dart';

void main() async {
  await initiateForTest();

  group('SvtPreset & maxOut', () {
    test('BattleSimUserData json backward compatibility and SvtPreset round-trip', () {
      final legacy = BattleSimUserData.fromJson(<String, dynamic>{});
      expect(legacy.svtPresets, isEmpty);

      final emptySvtTemplate = SvtPreset(
        name: 'Pure Template',
        isTemplate: true,
        bondLv: 15,
        data: SvtSaveData(lv: 120, tdLv: 5, atkFou: 3000, hpFou: 3000, cardStrengthens: [500, 500, 500, 500, 500]),
      );
      final encoded = BattleSimUserData(svtPresets: [emptySvtTemplate]).toJson();
      final decoded = BattleSimUserData.fromJson(encoded);

      expect(decoded.svtPresets, hasLength(1));
      final restored = decoded.svtPresets.single;
      expect(restored.name, 'Pure Template');
      expect(restored.isTemplate, isTrue);
      expect(restored.bondLv, 15);
      expect(restored.data.lv, 120);
      expect(restored.data.atkFou, 3000);
      expect(restored.data.hpFou, 3000);
      expect(restored.data.cardStrengthens, [500, 500, 500, 500, 500]);
    });

    test('maxOut maximizes servant stats, skills, appends, paws, class board and equipped CE', () {
      final altria = PlayerSvtData.id(100100)
        ..limitCount = 1
        ..lv = 1
        ..bondLv = 0
        ..tdLv = 1
        ..atkFou = 0
        ..hpFou = 0
        ..skillLvs = [1, 1, 1]
        ..appendLvs = [0, 0, 0, 0, 0]
        ..cardStrengthens = [0, 0, 0, 0, 0]
        ..grandSvt = true;

      final sampleCe = db.gameData.craftEssencesById.values.firstWhere((ce) => ce.lvMax >= 80);
      altria.equip1 = SvtEquipData(ce: sampleCe, limitBreak: false, lv: 1);

      altria.maxOut();

      expect(altria.limitCount, 4);
      expect(altria.lv, 120);
      expect(altria.bondLv, kBondLvMax);
      expect(altria.tdLv, 5);
      expect(altria.atkFou, 3000);
      expect(altria.hpFou, 3000);
      expect(altria.skillLvs, [10, 10, 10]);
      expect(altria.appendLvs, [10, 10, 10, 10, 10]);
      expect(altria.cardStrengthens, [500, 500, 500, 500, 500]);
      expect(altria.equip1.limitBreak, isTrue);
      expect(altria.equip1.lv, sampleCe.lvMax);

      final saberBoard = ClassBoard.getClassBoard(altria.svt!.classId);
      if (saberBoard != null) {
        expect(altria.classBoardData.classBoardSquares.length, ClassBoardPlan.full(saberBoard).enhancedSquares.length);
      }
      final grandBoard = ClassBoard.getGrandClassBoard(altria.svt!.classId);
      if (grandBoard != null) {
        expect(
          altria.classBoardData.grandClassBoardSquares.length,
          ClassBoardPlan.full(grandBoard).enhancedSquares.length,
        );
      }
    });

    test('applyPreset works in both same-servant full mode and cross-servant template mode', () async {
      final codes = db.gameData.commandCodesById.values.take(5).toList();
      final normalCe = db.gameData.craftEssencesById.values.firstWhere(
        (ce) => ce.rarity == 5 && !ce.flags.contains(SvtFlag.svtEquipFriendShip),
      );
      final altria = PlayerSvtData.id(100100)..grandSvt = true;
      altria.maxOut();
      altria.equip1 = SvtEquipData(ce: normalCe, limitBreak: true, lv: normalCe.lvMax);
      altria.commandCodes = List<CommandCode?>.generate(5, (i) => i < codes.length ? codes[i] : null);
      if (altria.svt!.bondEquips.isNotEmpty) {
        final altriaBondCe = db.gameData.craftEssencesById[altria.svt!.bondEquips.first];
        if (altriaBondCe != null) {
          altria.equip2 = SvtEquipData(ce: altriaBondCe, limitBreak: true, lv: altriaBondCe.lvMax);
        }
      }
      altria.classBoardData.grandBondEquipSkillChange = true;

      final preset = altria.toPreset(name: 'Full Max Template', isTemplate: true)!;
      final roundTripped = SvtPreset.fromJson(preset.toJson());

      // Apply as cross-servant template to Koyanskaya of Light (Assassin, 604200).
      final koyan = PlayerSvtData.id(604200)
        ..lv = 1
        ..bondLv = 1
        ..tdLv = 1
        ..atkFou = 0
        ..hpFou = 0
        ..skillLvs = [1, 1, 1]
        ..appendLvs = [0, 0, 0, 0, 0]
        ..supportType = SupportSvtType.friend;

      await koyan.applyPreset(roundTripped, includeServant: false);

      expect(koyan.svt!.id, 604200);
      expect(koyan.supportType, SupportSvtType.friend);
      expect(koyan.lv, 120);
      expect(koyan.bondLv, kBondLvMax);
      expect(koyan.tdLv, 5);
      expect(koyan.atkFou, 3000);
      expect(koyan.hpFou, 3000);
      expect(koyan.skillLvs, [10, 10, 10]);
      expect(koyan.appendLvs, [10, 10, 10, 10, 10]);
      expect(koyan.cardStrengthens, [500, 500, 500, 500, 500]);
      expect(koyan.commandCodes.map((e) => e?.id).toList(), altria.commandCodes.map((e) => e?.id).toList());
      expect(koyan.equip1.ce?.id, normalCe.id);
      expect(koyan.grandSvt, isTrue);
      expect(koyan.classBoardData.grandBondEquipSkillChange, isTrue);

      if (koyan.svt!.bondEquips.isNotEmpty) {
        expect(koyan.equip2.ce?.id, koyan.svt!.bondEquips.first);
      }

      final assassinBoard = ClassBoard.getClassBoard(koyan.svt!.classId);
      if (assassinBoard != null) {
        expect(
          koyan.classBoardData.classBoardSquares.length,
          ClassBoardPlan.full(assassinBoard).enhancedSquares.length,
        );
      }

      // Apply with includeServant=true switches servant back to Altria.
      await koyan.applyPreset(roundTripped, includeServant: true);
      expect(koyan.svt!.id, 100100);
      expect(koyan.bondLv, kBondLvMax);
      expect(koyan.supportType, SupportSvtType.friend);
    });
  });
}
