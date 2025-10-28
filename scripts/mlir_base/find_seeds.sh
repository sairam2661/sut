#!/bin/bash

python -m mlirmut.scripts.find_seeds \
	/data/saiva/MLIR-Experiments/workdir/mlir_custom \
	/data/saiva/MLIR-Experiments/workdir/mlir_custom_filtered \
	--exclude-path /data/saiva/sut/workdir/llvm-project/build \
	--mlir-opt-path /data/saiva/MLIRFuzz/workdir/llvm-project/build/bin/mlir-opt \
	--grammar /data/saiva/SynthFuzz/eval/mlir/mlir_2023.g4 \
	--start-rule start_rule
