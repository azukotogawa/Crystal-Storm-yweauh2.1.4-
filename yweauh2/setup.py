from setuptools import setup

APP = ['main.py']
DATA_FILES = ['files', 'config1.py', 'world.py', 'chunk_manager.py', 'world_drawer.py', 'player.py', 'groups.py', 'sprites.py', 'settings.py']
OPTIONS = {
    'argv_emulation': True,
    'iconfile': 'ixon.icns',
    'packages': ['pygame-ce', 'perlin_noise', 'noise', 'numpy'],
    'includes': ['pygame-ce'],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)