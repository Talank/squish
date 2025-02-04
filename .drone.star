def main(ctx):
  versions = [
    'latest',
  ]

  arches = [
    'amd64',
  ]

  config = {
    'version': 'latest',
    'arch': 'amd64',
    'trigger': [],
    'repo': ctx.repo.name,
    'squishversion': '6.7-20210421-1504-qt512x-linux64',
    'description': 'Squish for ownCloud CI',
    's3secret': {
       'from_secret': 'squish_download_s3secret',
    },
  }

  for version in versions:
    config['version'] = version

    if config['version'] == 'latest':
      config['path'] = 'latest'
    else:
      config['path'] = 'v%s' % config['version']

  stages = [ docker(config) ]

  after = [
    documentation(config),
    notification(config),
  ]

  for s in stages:
    for a in after:
      a['depends_on'].append(s['name'])

  return stages + after

def docker(config):
  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': '%s-%s' % (config['arch'], config['path']),
    'platform': {
      'os': 'linux',
      'arch': config['arch'],
    },
    'steps': steps(config),
    'image_pull_secrets': [
      'registries',
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/pull/**',
      ],
    },
  }

def documentation(config):
  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'documentation',
    'platform': {
      'os': 'linux',
      'arch': 'amd64',
    },
    'steps': [
      {
        'name': 'link-check',
        'image': 'ghcr.io/tcort/markdown-link-check:3.8.7',
        'commands': [
          '/src/markdown-link-check README.md',
        ],
      },
      {
        'name': 'publish',
        'image': 'chko/docker-pushrm:1',
        'environment': {
          'DOCKER_PASS': {
            'from_secret': 'public_password',
          },
          'DOCKER_USER': {
            'from_secret': 'public_username',
          },
          'PUSHRM_FILE': 'README.md',
          'PUSHRM_TARGET': 'owncloudci/${DRONE_REPO_NAME}',
          'PUSHRM_SHORT': config['description'],
        },
        'when': {
          'ref': [
            'refs/heads/master',
          ],
        },
      },
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
        'refs/pull/**',
      ],
    },
  }


def notification(config):
  steps = [{
    'name': 'notify',
    'image': 'plugins/slack',
    'settings': {
      'webhook': {
        'from_secret': 'private_rocketchat',
      },
      'channel': 'builds',
    },
    'when': {
      'status': [
        'success',
        'failure',
      ],
    },
  }]

  downstream = [{
    'name': 'downstream',
    'image': 'plugins/downstream',
    'settings': {
      'token': {
        'from_secret': 'drone_token',
      },
      'server': 'https://drone.owncloud.com',
      'repositories': config['trigger'],
    },
    'when': {
      'status': [
        'success',
      ],
    },
  }]

  if config['trigger']:
    steps = downstream + steps

  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'notification',
    'platform': {
      'os': 'linux',
      'arch': 'amd64',
    },
    'clone': {
      'disable': True,
    },
    'steps': steps,
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
      ],
      'status': [
        'success',
        'failure',
      ],
    },
  }

def dryrun(config):
  return [{
    'name': 'dryrun',
    'image': 'plugins/docker',
    'environment':{
      'S3SECRET': config['s3secret']
    },
    'settings': {
      'dry_run': True,
      'tags': [
        config['squishversion'],
        config['version'],
      ],
      'dockerfile': '%s/Dockerfile.%s' % (config['path'], config['arch']),
      'repo': 'owncloudci/%s' % config['repo'],
      'context': config['path'],
      'build_args': [
        'SQUISHVERSION=%s' % config['squishversion'],
      ],
      'build_args_from_env': [
        'S3SECRET'
      ],
    },
    'when': {
      'ref': [
        'refs/pull/**',
      ],
    },
  }]

def publish(config):
  return [{
    'name': 'publish',
    'image': 'plugins/docker',
    'environment':{
      'S3SECRET': config['s3secret']
    },
    'settings': {
      'username': {
        'from_secret': 'public_username',
      },
      'password': {
        'from_secret': 'public_password',
      },
      'tags': [
        config['squishversion'],
        config['version'],
      ],
      'dockerfile': '%s/Dockerfile.%s' % (config['path'], config['arch']),
      'repo': 'owncloudci/%s' % config['repo'],
      'context': config['path'],
      'pull_image': False,
      'build_args': [
        'SQUISHVERSION=%s' % config['squishversion'],
      ],
      'build_args_from_env': [
        'S3SECRET'
      ],
    },
    'when': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
      ],
    },
  }]



def steps(config):
  return dryrun(config) + publish(config)
