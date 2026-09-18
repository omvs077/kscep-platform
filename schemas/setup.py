from setuptools import setup, find_packages

setup(
    name="kscep_schemas",
    version="1.0.0",
    packages=find_packages(),
    package_data={
        "schemas": ["*.json"],
    },
    install_requires=[
        "jsonschema>=4.0.0",
    ],
)
