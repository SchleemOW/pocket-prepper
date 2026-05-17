#!/usr/bin/env python3
"""
Converts all-MiniLM-L6-v2 to Core ML format for on-device embedding on iPhone.
Output: MiniLM.mlpackage (drop into Xcode project)
"""

import numpy as np
from pathlib import Path

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_PATH = Path("MiniLM.mlpackage")


def mean_pooling(token_embeddings, attention_mask):
    import torch
    mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
    return torch.sum(token_embeddings * mask_expanded, 1) / torch.clamp(mask_expanded.sum(1), min=1e-9)


def convert():
    import torch
    import coremltools as ct
    from transformers import AutoTokenizer, AutoModel
    import torch.nn as nn

    print("Loading model and tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    hf_model = AutoModel.from_pretrained(MODEL_NAME)
    hf_model.eval()

    # Wrapper that does tokenization + pooling + normalization in one forward pass
    class MiniLMWrapper(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            embeddings = mean_pooling(outputs.last_hidden_state, attention_mask)
            # L2 normalize
            embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
            return embeddings

    wrapper = MiniLMWrapper(hf_model)
    wrapper.eval()

    # Trace with a sample input (max 128 tokens for efficiency)
    print("Tracing model...")
    sample_text = "How do I find water in a forest?"
    tokens = tokenizer(
        sample_text,
        return_tensors="pt",
        padding="max_length",
        max_length=128,
        truncation=True,
    )

    with torch.no_grad():
        traced = torch.jit.trace(
            wrapper,
            (tokens["input_ids"], tokens["attention_mask"])
        )

    # Convert to Core ML
    print("Converting to Core ML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids",      shape=tokens["input_ids"].shape,      dtype=np.int32),
            ct.TensorType(name="attention_mask",  shape=tokens["attention_mask"].shape, dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32),
        ],
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,  # Uses Neural Engine on iPhone
    )

    # Add metadata
    mlmodel.short_description = "MiniLM-L6-v2 sentence embeddings for Pocket Prepper"
    mlmodel.input_description["input_ids"]     = "Tokenized input (max 128 tokens)"
    mlmodel.input_description["attention_mask"] = "Attention mask"
    mlmodel.output_description["embedding"]    = "384-dim normalized embedding"

    mlmodel.save(str(OUTPUT_PATH))
    print(f"\nSaved: {OUTPUT_PATH}")
    print(f"Size:  {sum(f.stat().st_size for f in OUTPUT_PATH.rglob('*') if f.is_file()) / 1024 / 1024:.1f} MB")
    print("\nDrop MiniLM.mlpackage into your Xcode project to use it.")


if __name__ == "__main__":
    convert()
