# Circuit Artifacts

This directory contains the compiled circuit artifacts needed for zero-knowledge proof generation in the Privacy Pool paymaster system.

## Directory Structure

```
circuits/
├── build/
│   ├── commitment/
│   │   ├── commitment.wasm          # WASM for commitment circuit witness generation
│   │   ├── generate_witness.js      # Helper script for witness generation
│   │   └── witness_calculator.js    # Witness calculation utilities
│   └── withdraw/
│       ├── withdraw.wasm            # WASM for withdrawal circuit witness generation
│       ├── generate_witness.js      # Helper script for witness generation
│       └── witness_calculator.js    # Witness calculation utilities
└── keys/
    ├── commitment.vkey              # Verification key for commitment circuit
    ├── commitment.zkey              # Proving key for commitment circuit  
    ├── withdraw.vkey                # Verification key for withdrawal circuit
    └── withdraw.zkey                # Proving key for withdrawal circuit (17MB)
```

## File Descriptions

### WASM Files
- **commitment.wasm** (2.3MB) - Compiled commitment circuit for witness generation
- **withdraw.wasm** (2.5MB) - Compiled withdrawal circuit for witness generation

### Proving Keys (.zkey)
- **commitment.zkey** (880KB) - Groth16 proving key for commitment proofs
- **withdraw.zkey** (17MB) - Groth16 proving key for withdrawal proofs

### Verification Keys (.vkey)
- **commitment.vkey** (3.4KB) - Verification key used by commitment verifier contract
- **withdraw.vkey** (4.1KB) - Verification key used by withdrawal verifier contract

## Usage in E2E Tests

These artifacts are used by `WithdrawalProofGenerator.ts` to generate real zero-knowledge proofs:

```typescript
const CIRCUIT_PATHS = {
  withdrawal: {
    wasm: './circuits/build/withdraw/withdraw.wasm',
    zkey: './circuits/keys/withdraw.zkey'  
  },
  commitment: {
    wasm: './circuits/build/commitment/commitment.wasm',
    zkey: './circuits/keys/commitment.zkey'
  }
};
```

## Source

These artifacts were copied from `privacy-pools-core/packages/circuits/` and represent the final trusted setup ceremony outputs.

## Git LFS

Consider using Git LFS for the large zkey files:
```bash
git lfs track "circuits/keys/*.zkey"
```