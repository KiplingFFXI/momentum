"""Check the 1.6 merit release against 1.5, allowing only its specified changes."""
import argparse
from copy import deepcopy
from pathlib import Path
import tempfile
import zipfile

from compare_release import trace
import run


ADDED = {'merits_session', 'merit_headroom', 'lp_remaining', 'merit_eta'}


def compatible(expected, actual):
    expected, actual = deepcopy(expected), deepcopy(actual)
    old, new = expected['view'], actual['view']
    headroom = max(0, old['merit_cap'] - old['merits'])
    full = headroom == 0
    assert new.pop('merit_headroom') == headroom
    assert new.pop('merit_full') == full
    assert new['exp'].pop('blocked') is False
    assert 'reason' not in new['exp']
    assert new['lp'].pop('blocked') == full
    if full:
        assert new['lp'].pop('reason') == 'Spend some merit points to make room for another.'
        assert 'eta' not in new['lp']
        old['lp'].pop('eta', None)
        if old['mode'] == 'lp':
            assert 'eta' not in new
            old.pop('eta', None)
    else:
        assert 'reason' not in new['lp']
    assert new == old, 'Unexpected tracking change'

    current = [actual['readouts'][key] for key in sorted(actual['readouts'])]
    added = [item for item in current if item['id'] in ADDED]
    assert {item['id'] for item in added} == ADDED and len(added) == 4
    current = [item for item in current if item['id'] not in ADDED]
    previous = [expected['readouts'][key] for key in sorted(expected['readouts'])]
    assert len(current) == len(previous)
    for before, after in zip(previous, current):
        if before['id'] in ('rate', 'exp_rate', 'lp_rate'):
            before['label'] = before['label'].replace('/hr', '/HR')
        if before['id'] == 'merit_rate':
            rate = old['lp'].get('rate')
            before['value'] = '--' if rate is None else format(rate / 10000, '.2f')
        if before['id'] in ('remaining', 'eta') and old['mode'] == 'lp' and full:
            before['value'] = 'Spend merits'
        assert after == before, 'Unexpected readout change: ' + before['id']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    args = parser.parse_args()
    current = trace(run.ADDON)
    with tempfile.TemporaryDirectory(prefix='momentum_merit_previous_') as folder:
        root = Path(folder)
        with zipfile.ZipFile(args.baseline) as archive:
            for member in archive.infolist():
                if not (root / member.filename).resolve().is_relative_to(root) or not member.filename.startswith('momentum/'):
                    raise ValueError('Unexpected archive path: ' + member.filename)
            archive.extractall(root)
        baseline = trace(root / 'momentum')
    assert len(current) == len(baseline)
    for index, expected in baseline.items():
        try:
            compatible(expected, current[index])
        except AssertionError as error:
            raise AssertionError('Trace view %d: %s' % (index, error)) from error
    print('PASS: %d tracking/readout sets match 1.5 except the asserted 1.6 merit and unit changes.' % len(current))


if __name__ == '__main__':
    main()
