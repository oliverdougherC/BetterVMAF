#!/usr/bin/env python3
"""Read-only production prerequisite audit. Uses authenticated gh; never reads secret values."""
import argparse
import base64
import json
import re
import subprocess
import sys

REPO = 'oliverdougherC/BetterVMAF'
SECRETS = ['SPARKLE_PRIVATE_KEY', 'APPLE_CERTIFICATE_P12', 'APPLE_CERTIFICATE_PASSWORD',
           'APPLE_NOTARY_KEY', 'APPLE_NOTARY_KEY_ID', 'APPLE_NOTARY_ISSUER_ID']


def api(path):
    result = subprocess.run(['gh', 'api', f'repos/{REPO}/{path}'], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'Cannot inspect {path}: {result.stderr.strip()}')
    return json.loads(result.stdout)


def audit():
    checks = []
    def check(name, condition, detail):
        checks.append({'check': name, 'ready': bool(condition), 'detail': detail})
    def inspect(name, function):
        try:
            function()
        except (RuntimeError, KeyError, ValueError, TypeError) as error:
            check(name, False, str(error))
    def infrastructure():
        check('Release immutability', api('immutable-releases')['enabled'], 'Required before publishing')
        check('Pages Actions source', api('pages')['build_type'] == 'workflow', 'Does not deploy the production feed')
        protection = api('branches/main/protection')
        required = protection.get('required_status_checks', {})
        check('Main CI protection', required.get('strict') and
              'Build and test (macOS 15, Xcode 16.4)' in required.get('contexts', []) and
              not protection['allow_force_pushes']['enabled'] and not protection['allow_deletions']['enabled'],
              'Required CI, up-to-date branch, no force push or deletion')
        rulesets = [api(f"rulesets/{rule['id']}") for rule in api('rulesets')]
        active = [rule for rule in rulesets if rule['enforcement'] == 'active' and rule['target'] == 'tag'
                  and 'refs/tags/v*' in rule['conditions']['ref_name']['include']
                  and not rule['conditions']['ref_name']['exclude']]
        check('Release tags cannot move or be deleted', all(any(
            not rule.get('bypass_actors') and kind in {r['type'] for r in rule['rules']}
            for rule in active) for kind in ['update', 'deletion']), 'No bypass for v* updates/deletion')
        check('Release tag creation restricted', any(
            'creation' in {r['type'] for r in rule['rules']} and
            rule.get('bypass_actors') == [{'actor_id': 5, 'actor_type': 'RepositoryRole', 'bypass_mode': 'always'}]
            for rule in active), 'Only repository admins create v* tags')
        workflow = api('actions/permissions/workflow')
        check('Workflow default token', workflow['default_workflow_permissions'] == 'read' and
              not workflow['can_approve_pull_request_reviews'], 'Read-only; no PR self-approval')
    inspect('GitHub infrastructure access', infrastructure)
    for name in ['release-signing', 'github-pages']:
        def environment(name=name):
            env = api(f'environments/{name}')
            check(f'{name} restrictions enabled', env['deployment_branch_policy'] == {
                'protected_branches': False, 'custom_branch_policies': True}, 'Custom branch/tag restrictions')
            policies = api(f'environments/{name}/deployment-branch-policies')['branch_policies']
            check(f'{name} allowed refs', {(p['type'], p['name']) for p in policies} == {
                ('branch', 'main'), ('tag', 'v*')}, 'Only main and v*; no feature branches')
        inspect(name, environment)
    def credentials():
        variables = {v['name']: v['value'] for v in api('actions/variables')['variables']}
        public = variables.get('SPARKLE_PUBLIC_KEY', '')
        try:
            valid_public = len(base64.b64decode(public, validate=True)) == 32
        except ValueError:
            valid_public = False
        check('SPARKLE_PUBLIC_KEY', valid_public, 'Repository variable; requires stable identity and verified offline backup')
        check('APPLE_TEAM_ID', re.fullmatch('[A-Z0-9]{10}', variables.get('APPLE_TEAM_ID', '')), 'Repository variable; Apple account')
        names = {s['name'] for s in api('environments/release-signing/secrets')['secrets']}
        for name in SECRETS:
            check(name, name in names, 'release-signing environment secret; presence only, not credential validity')
    inspect('Credential metadata access', credentials)
    return checks


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    checks = audit()
    if args.json:
        print(json.dumps(checks, indent=2))
    else:
        for item in checks:
            print(f"{'READY' if item['ready'] else 'MISSING'}  {item['check']}: {item['detail']}")
        print('\nSecret presence is not proof of a usable identity or notarization. Run the production preflight after provisioning.')
    sys.exit(0 if checks and all(c['ready'] for c in checks) else 1)
