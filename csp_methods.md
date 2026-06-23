# Published generative models for inorganic crystal structure generation

Last updated: 2026-06-18 (architecture verified). Scope: inorganic crystals only.

Used by `idea` subagent as the novelty boundary.

## Diffusion (continuous / score-based denoising)

- **CDVAE** (2022): `vae`+`score-matching` + `DimeNet++` enc / `GemNet-dQ` dec `[equivariant-GNN]`. VAE encoder + score-based Langevin decoder for periodic materials; foundational MP-20 baseline. ICLR 2022 / arXiv:2110.06197.
- **DiffCSP** (2023): `diffusion` + `CSPNet` `[equivariant-GNN]`. Joint equivariant diffusion over lattice (Cartesian) and fractional coords; CSPNet uses Fourier features on frac coords. NeurIPS 2023 / arXiv:2309.04475.
- **DiffCSP++** (2024): `diffusion` + `CSPNet` (modified) `[equivariant-GNN]`. Space-group / Wyckoff-conditioned extension of DiffCSP; reuses CSPNet with O(3)-invariant k-rep + space-group projection. ICLR 2024.
- **MatterGen** (2025): `diffusion` + `GemNet` (adapted score net) `[equivariant-GNN]`. Joint diffusion over atom types, coords, lattice; property-conditional fine-tuning via adapter modules. Nature 2025.
- **UniMat** (2024): `diffusion` + `3D U-Net` `[CNN]`. Unified 4D periodic-table tensor representation; repurposed video 3D U-Net (conv + attention). arXiv:2311.09235.
- **SyMat** (2023): `diffusion` + `SphereNet` `[equivariant-GNN]`. Symmetry-enhanced CDVAE variant; spherical message passing shared by VAE encoder + coord score model. NeurIPS 2023.
- **GemsDiff** (2023): `diffusion` + `GemsNet` `[equivariant-GNN]`. GemNet-inspired equivariant GNN extended to deform the lattice. AI4Mat 2023.
- **DP-CDVAE** (2024): `diffusion` + `DimeNet++` enc / `GemNet-T` denoiser `[equivariant-GNN]`. DDPM-based CDVAE variant; reuses CDVAE backbones with a GemNet-T diffusion denoiser. Sci. Reports 2024.
- **Cond-CDVAE / Con-CDVAE** (2024): `diffusion`+`vae` + `DimeNet++` enc / `GemNet-dQ` dec `[equivariant-GNN]`. Composition / pressure-conditioned CDVAE; reuses CDVAE backbones with a conditional latent. npj Comp. Mat. 2024 (arXiv:2403.10846).
- **CrysTens** (2024): `diffusion` (also GAN variant) + `Imagen cascaded U-Net` `[CNN]`. Image-like 64×64×4 pairwise-distance representation denoised by an image U-Net.
- **StructRepDiff** (2024): `diffusion` + `1D-conv U-Net` `[CNN]`. Diffusion in EAM descriptor space; ResNet + multihead-attention U-Net.
- **EH-Diff** (2025): `diffusion` + `EHNN` (equivariant hypergraph NN) `[hypergraph-NN]`. Equivariant hypergraph diffusion for periodic crystals; novel EHNN denoiser (not CSPNet). arXiv:2501.18850.
- **TransVAE-CSP** (2025): `vae` + `equivariant attention Transformer` `[equivariant-transformer]`. Irrep dot-product attention encoder + RBF distance expansion; no diffusion component.
- **TGDMat** (2025): `diffusion` + `CSPNet` (extended) + `MatSciBERT` text enc `[equivariant-GNN]`. Text-guided contextual diffusion; DiffCSP CSPNet extended for joint diffusion.
- **DAO-G** (2025): `diffusion`+`ebm` + `Crysformer` (equivariant graph Transformer) `[equivariant-GNN]`. Energy-based diffusion; custom graph-Transformer replacing the DiffCSP GNN.
- **Chemeleon** (2025): `diffusion` + `CSPNet` (DiffCSP-style) + Crystal-CLIP text enc `[equivariant-GNN]`. Multi-modal text-guided diffusion via cross-modal contrastive alignment. Digital Discovery / PMC 2025.
- **SymmCD** (2025): `diffusion` + `CSPNet-derived MPNN` (non-equivariant) `[GNN]`. Symmetry-preserving diffusion over Wyckoff binary matrix + coords; fully-connected MPNN on a canonical cell frame. ICLR 2025 / arXiv:2502.03638.
- **DiffCrysGen** (2025): `score-matching` + `EDM noise-conditional U-Net` `[CNN]`. SDE/Karras-EDM score net (~1.3M params) over a 2D point-cloud / matrix representation; no GNN. arXiv:2505.07442.
- **CrystalDiT** (2025): `diffusion` + `DiT` (Diffusion Transformer) `[transformer]`. Unified single-stream DiT (18 blocks / 512-dim / 8-head, AdaLN) over 23-token crystal sequence. arXiv:2508.16614.
- **Crystalite** (2026): `diffusion` + standard `Transformer` (non-equivariant) `[transformer]`. EDM-style joint diffusion; subatomic tokenization (period/group/valence) + GEM attention bias for periodic geometry instead of equivariant GNN. arXiv:2604.02270.
- **Space-Group Equivariant Crystal Diffusion** (2025): `diffusion` + SE(3)-invariant/equivariant sampler (+ transformer for Wyckoff/element) `[equivariant-GNN]`. Hybrid denoiser combining SE(3)-equivariant components with Wyckoff/element transformer; not a single unified GNN backbone. arXiv:2505.10994.
- **Symmetry-aware Conditional Diffusion** (2026 preprint): `diffusion` + `WyckoffGNN` (non-equivariant MPNN; symmetry via Wyckoff-space operations, not equivariant ops) `[GNN]`. Symmetry-conditional crystal diffusion. arXiv:2601.08115.
- **Equivariant Diffusion for CSP** (2025): `diffusion` + `equivariant-GNN` (unspecified). arXiv:2512.07289.
- **PXRDGen** (2025): `diffusion` (or flow) + `CSPNet` dec + CNN/Transformer XRD enc `[equivariant-GNN]`. PXRD-conditional generator + Rietveld refinement. Nat. Commun. 2025 / arXiv:2409.04727.

## Flow matching

- **FlowMM** (2024): `flow-matching` + custom `equivariant-GNN` (own backbone, not DiffCSP's CSPNet) `[equivariant-GNN]`. Riemannian flow matching adapted to crystal symmetries; explicitly distinguishes itself from DiffCSP-based architectures. ICML 2024 / arXiv:2406.04713.
- **FlowLLM** (2024): `flow-matching`+`autoregressive` + `Llama-2-70B` base / `EGNN`-based RFM refiner `[LLM`+`equivariant-GNN]`. LLM as base distribution, EGNN-based (not CSPNet) refiner for coords/lattice. NeurIPS 2024 / arXiv:2410.23405.
- **CrystalFlow** (2024-25): `flow-matching` + `CSPNet` (DiffCSP GNN, adapted) `[equivariant-GNN]`. Pressure-conditioned continuous normalizing flows; multi-head vector fields. PMC 2025 / arXiv:2412.11693.
- **OMatG** (2025): `stochastic interpolants` + `CSPNet` (from DiffCSP) `[equivariant-GNN]`. Unified stochastic-interpolant framework covering diffusion and flow as special cases; 6-layer CSPNet with velocity + denoiser heads. ICML 2025 / arXiv:2502.02582.
- **Multimodal Crystal Flow** (2026 preprint): `flow-matching` + `DiT` (all-atom) `[transformer]`. Any-to-any modality flow for unified crystal modeling. arXiv:2602.20210.

## VAE

- **iMatGen** (2019): `vae` + `3D voxel conv-autoencoder` `[CNN]` (voxel). Hierarchical voxel VAE for vanadium oxides. Matter 2019.
- **FTCP** (2022): `vae` + `Conv1D enc / Conv1DTranspose dec` `[CNN]`. Fourier-transformed (reciprocal+real space) VAE over the 1D FTCP signal (not 2D). Matter 2022.
- **PCVAE** (2023): `vae` + `MLP` (fully-connected). Physics-informed descriptors (Bravais lattice, space group, lattice constants) via fully-connected encoder/decoder.
- **WyCryst** (2024): `vae` + `MLP` (over Wyckoff matrix) `[MLP`+`GNN]`. Wyckoff-positions property-guided VAE; dense layers. arXiv:2311.17916.
- **LCOM** (2023): `vae`+`diffusion` + `DimeNet++` enc / `GemNet` dec `[equivariant-GNN]`. Latent Conservative Objective Models optimizing in a pretrained CDVAE latent space.

## GAN

- **CrystalGAN** (2018): `gan` + `MLP` (cross-domain, point cloud). Hydride generation. arXiv:1810.11203.
- **DD3DCS** (2019): `gan` + `3D-CNN` (voxel) `[CNN]`. Voxel electron-density-grid generator (VAE + 3D U-Net pipeline). *(identity low-confidence)*
- **CondGAN** (2019): `gan` + `MLP` (bag-of-atoms + descriptors). Composition-conditioned GAN. arXiv:1910.11499.
- **MatGAN** (2020): `gan` + `deconv-CNN` (WGAN; FC → reshape → deconv layers; discriminator uses conv layers) `[CNN]`. Element-conditioned composition GAN over 85×8 one-hot composition matrix; outputs compositions, not full structures. npj Comp. Mat. 2020 / arXiv:1911.05020.
- **GANCSP / CrystalGAN-CSP** (2020): `gan` + `MLP` (WGAN, point cloud). Composition-aware GAN for CSP; shared-MLP critic + classifier. ACS Cent. Sci. 2020 / arXiv:2004.01396.
- **ICSG3D** (2020): `vae` + `3D-CNN` (voxel) `[CNN]`. Conditional Deep Feature Consistent VAE (Cond-DFC-VAE) + 3D U-Net segmentation for atomic coordinate recovery; energy-conditioned; no GAN component. JCIM 2020.
- **CubicGAN** (2021): `gan` + `MLP` (WGAN-GP). Cubic-system generator; element/space-group embeddings + lattice params + coords.
- **CCDCGAN** (2021, ext. 2022): `vae`+`gan` + `DCGAN` (2D latent image) `[CNN]`. Two-stage VAE-GAN; transposed-conv generator over an autoencoded 2D crystal image.
- **PGCGM** (2023): `gan` + `Conv2D`+`MLP` (Wyckoff/affine) `[CNN]`. Physics-informed Wyckoff GAN for ternaries; 2D-conv on affine matrices.
- **CGWGAN** (2024): `gan` + `MLP` (Wyckoff). Two-step template-based Wyckoff GAN; FC generator emitting ASU + space-group + lattice.
- **LCMGM** (2024): `vae`+`gan` + `Conv2D/Conv1D`+`Dense` `[CNN]`. Mesh-grid (reciprocal+real-space, FTCP-style) tensor with convolutional encoder/decoder + adversarial latent sampling. npj Comp. Mat. 2024.
- **NSGAN** (2024): `gan`+`rl-generative` (GA hybrid) + `MLP`. Hybrid GAN-genetic-algorithm over composition vectors for alloys.
- **VGD-CG** (2024): `gan`+`vae`+`diffusion` + `MLP` (unspecified). Property-targeted composition generator over composition vectors.

## Autoregressive / language model

- **XYZTransformer** (2023): `autoregressive` + `GPT-style decoder` (from scratch) `[LLM]`. GPT trained on XYZ/CIF/PDB-format structures.
- **CrystaLLM** (2024): `autoregressive` + `GPT-2` (nanoGPT) `[LLM]`. CIF-format LLM trained from scratch. Nat. Commun. 2024 / arXiv:2307.04340.
- **CrystalTextLLM** (2024): `autoregressive` + `Llama-2` (7B/13B/70B) `[LLM]`. Fine-tuned Llama-2 on text point-cloud crystals. ICLR 2024.
- **CrysText** (2024): `autoregressive` + `Llama-3.1-8B` (QLoRA; also Mistral-7B) `[LLM]`. CIF generation, RL variant with GRPO. ChemRxiv 2024.
- **CrystalFormer** (2024): `autoregressive` + custom `space-group-informed AR Transformer` `[transformer]`. Space-group-conditioned decoder-only transformer over Wyckoff tokens. arXiv:2403.15734.
- **WyFormer / Wyckoff Transformer** (2025): `autoregressive` + custom `permutation-invariant Transformer encoder` `[transformer]`. AR over Wyckoff tokens, no positional encoding. ICML 2025 / arXiv:2503.02407.
- **Matra-Genoa** (2025): `autoregressive` + custom `AR Transformer` `[transformer]`. Invertible Wyckoff tokenization + continuous coordinates, trained on 2M structures.
- **MatExpert** (2024): `autoregressive` + `Llama-3` (8B/70B); T5 retrieval encoders `[LLM]`. Multi-step conversational agent with contrastive retrieval.
- **GenMS** (2024): `autoregressive`+`diffusion` + `Gemini` (long-context LM) / custom atom diffusion + GNN `[LLM`+`GNN]`. Two-stage LLM formula → diffusion structure. arXiv:2409.06762.
- **Mat2Seq** (2025): `autoregressive` + `GPT` (CrystaLLM-style, GPT-2-class) `[LLM]`. Domain-agnostic invariant sequence encoding.
- **NatureLM-Mat3D** (2025): `autoregressive` + `Llama-3-8B` (fine-tuned) `[LLM]`. Multi-domain sequence LM over element/space-group/coordinate sequences.
- **MatLLMSearch** (2025): `autoregressive` + `Llama-3.1-70B` (no fine-tuning; also supports GPT-4o-mini etc.) `[LLM]`. Pre-trained LLM as evolutionary proposal agent; evolutionary algorithm wrapper (not RL). arXiv:2502.20933.
- **Uni-3DAR** (2025): `autoregressive` + custom `decoder-only AR transformer` `[transformer]`. Octree-compressed voxel spatial tokens, masked next-token.
- **UniGenX** (2025): `autoregressive`+`diffusion` + `decoder-only AR transformer` + diffusion head `[transformer]`. Hybrid autoregressive composition + coordinate diffusion.
- **deCIFer** (2025): `autoregressive` + `GPT-2/nanoGPT-style transformer` `[transformer]`. CIF autoregression conditioned on PXRD embeddings (CrystaLLM lineage). arXiv:2502.02189.
- **CrysReas / CrystalReasoner** (2026 preprint): `autoregressive`+`rl-generative` + `Qwen2.5-3B` (GRPO) `[LLM]`. RL-aligned property-conditioned LLM with reasoning tokens. arXiv:2605.14344.
- **MatterGPT** (2024): `autoregressive` + `GPT-style decoder` (nanoGPT-class, from scratch) `[transformer]`. Decoder-only transformer trained from scratch on SLICES tokens (not fine-tuned). arXiv:2408.07608.
- **SLI2Cry** (2023): `autoregressive` + `3-layer stacked GRU` `[RNN]`. Invertible SLICES representation with a GRU language model.

## Energy-based model (EBM)

- **ContinuouSP** (2025): `ebm` + `modified CGCNN` `[GNN]`. Energy-based CSP enforcing invariance + continuity. arXiv:2502.02026.

## RL / active-learning

- **Crystal-GFN** (2023): `rl-generative` (GFlowNet) + `MLP` forward policy. Space-group / prototype GFlowNet. NeurIPS 2023 workshop.
- **CHGlownet** (2023): `rl-generative` (GFlowNet) + `MLP` hierarchical policy (inferred) `[GNN]`. Graph-based generative flow network.
- **CrystalFormer-RL** (2025): `rl-generative` + `CrystalFormer` (AR Transformer) `[transformer]`. RL fine-tuning of CrystalFormer. arXiv:2504.02367.
- **OMatG-IRL** (2026 preprint): `rl-generative` + `CSPNet` (via OMatG) `[equivariant-GNN]`. Inference-time RL on velocity fields for CSP. arXiv:2602.00424.
- **RL-guided latent crystal diffusion** (Park & Walsh 2025): `rl-generative`+`latent-diffusion` + `ADiT`-style transformer + VAE `[transformer]`. GRPO policy gradient on a latent-diffusion backbone. arXiv:2511.07158.

## Hybrid / other

- **CrysBFN** (2025): `bfn` + periodic E(3)-equivariant `CSPNet`-style GNN (inferred) `[equivariant-GNN]`. Periodic E(3)-equivariant Bayesian flow network over the hyper-torus. ICLR 2025 / arXiv:2502.02016.
- **CrystalGRW** (2025): `geodesic-walk` + `EquiformerV2` `[equivariant-GNN]`. Torus-manifold diffusion via geodesic walks; equivariant attention GNN. arXiv:2501.08998.
- **KLDM** (2025): `diffusion` (manifold/velocity) + `CSPNet`-style GNN (inferred) `[GNN]`. Manifold diffusion via velocity space (Kinetic Langevin).
- **WyckoffDiff** (2025): `masked-discrete-diffusion` + `WyckoffGNN` (custom MPNN) `[GNN]`. Discrete diffusion over Wyckoff/space-group tokens on a fully-connected Wyckoff graph. arXiv:2502.06485.
- **ADiT** (All-atom Diffusion Transformer) (2025): `latent-diffusion` + `DiT` (+ VAE, non-equivariant) `[transformer]`. Unified latent diffusion over molecules + materials (materials portion = inorganic crystals). ICML 2025 / arXiv:2503.03965.
- **CGMD** (2024): `diffusion`+`vae`+`flow-matching` + `MLP` (unspecified). Combined diffusion/VAE/flow point-cloud model.
- **CrysLLMGen / LLM-meets-Diffusion** (2025): `autoregressive`+`diffusion` + `Llama-2-7B` + `CSPNet` `[LLM`+`equivariant-GNN]`. Llama-2-7B emits atoms; CSPNet diffusion refines coords/lattice. NeurIPS 2025 / arXiv:2510.23040.
- **Fourier Latent Crystallographic Diffusion** (2026 preprint): `latent-diffusion` + complex-valued `Transformer` (RoPE3D) `[transformer]`. Reciprocal-space latent diffusion denoiser. arXiv:2602.12045.
- **DeepCSP** (2024): `diffusion`+`vae` + `DimeNet++` enc / `GemNet-dQ` dec `[equivariant-GNN]`. Conditional CDVAE (Cond-CDVAE) variant with GemNet/DimeNet++ backbone. npj Comp. Mat. 2024 / arXiv:2403.10846.

## Excluded (not a learned generative model)

- **GNoME** (2023) — symmetry-aware elemental substitution + random structure search as the candidate generator, followed by a GNN energy-screening model.
