import json
import os

file_path = 'dist/reports/KISS-Smart-Batch-Installer-MKIII-deep-scan.json'

with open(file_path, 'r') as f:
    content = f.read()

# Remove the first line if it's 'Format: json'
if content.startswith('Format: json'):
    content = content.split('\n', 1)[1]

# Try to parse the JSON
try:
    # It's a stream of JSON objects, so we need to wrap it in an array
    json_objects = content.strip().replace('}', '},')
    # remove last comma
    if json_objects.endswith(','):
        json_objects = json_objects[:-1]
    json_data = json.loads(f'[{json_objects}]')
    print('JSON is valid')
except json.JSONDecodeError as e:
    print(f'JSON is invalid: {e}')
    # print the line of the error
    lines = content.split('\n')
    print(f'Error on line {e.lineno}: {lines[e.lineno-1]}')
