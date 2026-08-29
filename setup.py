from setuptools import setup

APP = ['lid_accordion.py']
DATA_FILES = [
    ('assets', ['assets/MacbookAccordion-AppIcon.png']),
]
OPTIONS = {
    'argv_emulation': True,
    'iconfile': 'assets/MacbookAccordion.icns',
    'packages': ['pygame', 'numpy', 'pybooklid', 'sounddevice'],
    'includes': ['sounddevice'],
    'plist': {
        'CFBundleName': 'MacbookAccordion',
        'CFBundleDisplayName': 'MacbookAccordion',
        'CFBundleIdentifier': 'games.macaca.macbookaccordion',
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '1.0.0',
        'NSHighResolutionCapable': True,
    },
}
setup(
    name='MacbookAccordion',
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
