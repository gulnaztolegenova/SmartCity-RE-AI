"""Explicit weather variants; original research constructors remain unchanged."""
from __future__ import annotations


def build_dp_weather(tf):
    layers = tf.keras.layers
    seq = layers.Input((24, 12), name="seq_in")
    flat = layers.Input((12,), name="flat_in")
    reference = layers.Input((2,), name="reference_in")
    branches = []
    for recurrent in (layers.LSTM, layers.GRU):
        x = recurrent(128, return_sequences=True)(seq)
        x = layers.Dropout(0.075)(x)
        x = recurrent(64, return_sequences=True)(x)
        branches.append(layers.GlobalAveragePooling1D()(x))
    x = seq
    for channels, dilation in ((128, 1), (128, 2), (64, 4)):
        x = layers.Conv1D(channels, 3, dilation_rate=dilation, padding="causal", activation="relu")(x)
    branches.append(layers.GlobalAveragePooling1D()(x))
    x = layers.Dense(160)(seq)
    for _ in range(2):
        z = layers.LayerNormalization()(x)
        attn = layers.MultiHeadAttention(num_heads=4, key_dim=40)(z, z, use_causal_mask=True)
        x = layers.Add()([x, layers.Dropout(0.15)(attn)])
        z = layers.LayerNormalization()(x)
        z = layers.Dense(256, activation="relu")(z)
        z = layers.Dropout(0.15)(z)
        x = layers.Add()([x, layers.Dense(160)(z)])
    branches.append(layers.GlobalAveragePooling1D()(x))
    gate = layers.Dense(4, activation="softmax", name="branch_gate")(flat)
    weighted = []
    for i, branch in enumerate(branches):
        projected = layers.Dense(96, activation="relu")(branch)
        weight = layers.Lambda(lambda g, j=i: g[:, j:j+1])(gate)
        weighted.append(layers.Multiply()([projected, weight]))
    z = layers.Concatenate()([*weighted, flat])
    z = layers.LayerNormalization()(z)
    z = layers.Dense(224, activation="relu")(z)
    z = layers.Dropout(0.15)(z)
    z = layers.Dense(128, activation="relu")(z)
    z = layers.Dropout(0.12)(z)
    outputs = []
    for j, target in enumerate(("solar", "wind")):
        delta = layers.Dense(1, name=f"delta_{target}", kernel_initializer="zeros")(z)
        baseline = layers.Lambda(lambda r, i=j: r[:, i:i+1])(reference)
        # A nonnegative weather response replaces the original observed-target
        # skip connection. This is a new trained variant, not the article weights.
        outputs.append(layers.Activation("relu", name=f"{target}_reg")(layers.Add()([delta, baseline])))
    cls = layers.Dense(96, activation="relu")(z)
    cls = layers.Dropout(0.12)(cls)
    outputs.extend([layers.Dense(1, activation="sigmoid", name=f"{target}_ext")(cls)
                    for target in ("solar", "wind")])
    return tf.keras.Model([seq, flat, reference], outputs, name="DP_STHPP_weather_v1")


def build_dualaxis_weather():
    import torch
    from torch import nn

    class DualAxisWeather(nn.Module):
        def __init__(self):
            super().__init__()
            self.val_proj = nn.Linear(1, 96)
            self.time_pos = nn.Parameter(torch.zeros(24, 96))
            self.feat_emb = nn.Parameter(torch.zeros(12, 96))
            def encoder():
                layer = nn.TransformerEncoderLayer(96, 4, 384, 0.1, batch_first=True,
                                                   activation="gelu", norm_first=True)
                return nn.TransformerEncoder(layer, 2, enable_nested_tensor=False)
            self.temporal, self.feature = encoder(), encoder()
            self.out_proj = nn.Linear(96, 1)

        def forward(self, x):
            b, length, d = x.shape
            if (length, d) != (24, 12):
                raise ValueError("DualAxis weather requires 24 x 12 weather inputs")
            x = self.val_proj(x.unsqueeze(-1)) + self.time_pos[None, :, None] + self.feat_emb[None, None]
            x = self.temporal(x.permute(0, 2, 1, 3).reshape(b*d, length, 96))
            x = x.reshape(b, d, length, 96).permute(0, 2, 1, 3).contiguous()
            x = self.feature(x.reshape(b*length, d, 96))
            return self.out_proj(x).reshape(b, length, d)

    return DualAxisWeather()
