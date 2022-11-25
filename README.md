# start-chain
GitHub action to spawn a Desmos chain


**Table of Contents**

* [Example workflow](#example-workflow)
* [Inputs](#inputs)


## Example workflow

```yaml
on: [pull_request]

name: Test chain interaction

jobs:
  chain_interaction:
    name: Test interaction with chain
    runs-on: ubuntu-latest

    steps:
      - name: Checkout 🛎️
        uses: actions/checkout@v2

      - name: Spawn chain
        uses: desmos-labs/start-chain@v1
        with:
          version: v4.6.3
      
      # Steps with the chain...
```

## Inputs

| Name           | Required | Description                                                     | Type   | Default |
|----------------|:--------:|-----------------------------------------------------------------|--------|---------|
| `version`      |  `true`  | Binary version to be used when starting the chain               | string |         |
| `genesis-file` |          | Path to the genesis file that should be used to start the chain | string | ""      |
| `pre-run`      |          | Script to be executed before the chain starts                   | string | ""      |
| `post-run`     |          | Script to be executed after the chain has started               | string | ""      |
