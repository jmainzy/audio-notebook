# audionotebook

Transcription tool with:

- sparse transcription
- note-taking
- search
- listening mode

## Offline transcription

The Transcribe button detects speech segments if none exist and fills only
empty, timed segments.

The model must be prepared locally once. Export a fine-tuned
MMS checkpoint (including its `vocab.json` and tokenizer configuration):

```sh
python3 -m venv .venv-mms-export
.venv-mms-export/bin/pip install -r python_tools/requirements-mms-export.txt
.venv-mms-export/bin/python python_tools/export_mms.py /path/to/checkpoint /path/to/mms-asr
```

Place the exported directory, including **all** external ONNX weight files,
at the `mms-asr` path shown in the error message when the model is missing.
On macOS this is normally the app's Application Support directory inside its
sandbox. Exporting requires several gigabytes of free disk space. Once the
model is installed, transcription does not require network access. The model
and its training data may have their own licensing and usage restrictions.
