# utils.py
import os
import sys

def resource_path(relative_path):
    """Get absolute path to resource, works for development and PyInstaller"""
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)


def get_save_dir():
    """Return the proper user data directory for saves"""
    from appdirs import user_data_dir
    return user_data_dir("yweauh2", "corrow")