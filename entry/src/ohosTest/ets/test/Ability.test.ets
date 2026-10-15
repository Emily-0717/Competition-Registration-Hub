import { describe, it, expect } from '@ohos/hypium';
import { Item, verify, percent, readiness } from '../../../main/ets/model/Domain';

export default function competitionHubTest() {
  describe('CompetitionHubRules', () => {
    it('EmptyRequirementsBlockSubmission', 0, () => {
      const track = new Item(); track.kind = 'Track'; track.id = 'track';
      expect(verify(track, [], [], Date.now()).some((f) => f.level === '未通过')).assertTrue();
    });
    it('EmptyProgressIsZero', 0, () => {
      expect(percent([])).assertEqual(0);
    });
    it('UnconfirmedEligibilityRequiresHuman', 0, () => {
      const track = new Item(); track.id = 'track'; track.kind = 'Track';
      const rule = new Item(); rule.id = 'rule'; rule.kind = 'EligibilityRule'; rule.parent = track.id; rule.status = '待确认';
      expect(verify(track, [rule], [], Date.now()).some((f) => f.human)).assertTrue();
    });
    it('ReadinessWithoutRulesIsZero', 0, () => {
      const track = new Item(); track.id = 'track';
      expect(readiness(track, [], Date.now()).score).assertEqual(0);
    });
  });
}
