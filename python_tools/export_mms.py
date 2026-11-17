"""Export a local MMS checkpoint to ONNX for offline inference."""

import argparse
import shutil
from pathlib import Path

import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    if args.output.exists() and any(args.output.iterdir()):
        raise FileExistsError(f"Output directory is not empty: {args.output}")
    if not (args.checkpoint / "adapter.mus.safetensors").is_file():
        raise FileNotFoundError("The checkpoint must include adapter.mus.safetensors")
    args.output.mkdir(parents=True, exist_ok=True)
    processor = Wav2Vec2Processor.from_pretrained(
        args.checkpoint, local_files_only=True
    )
    processor.tokenizer.set_target_lang("mus")
    model = Wav2Vec2ForCTC.from_pretrained(
        args.checkpoint, local_files_only=True, attn_implementation="eager"
    )
    model.load_adapter("mus", local_files_only=True)
    model.eval()

    class Logits(torch.nn.Module):
        def __init__(self, base):
            super().__init__()
            self.base = base

        def forward(self, input_values):
            return self.base(input_values).logits

    torch.onnx.export(
        Logits(model),
        (torch.zeros(1, 16000),),
        str(args.output / "model.onnx"),
        input_names=["input_values"],
        output_names=["logits"],
        dynamic_axes={"input_values": {1: "samples"}, "logits": {1: "frames"}},
        opset_version=17,
        dynamo=False,
        external_data=True,
    )
    shutil.copyfile(args.checkpoint / "vocab.json", args.output / "vocab.json")
    shutil.copyfile(
        args.checkpoint / "tokenizer_config.json",
        args.output / "tokenizer_config.json",
    )


if __name__ == "__main__":
    main()
