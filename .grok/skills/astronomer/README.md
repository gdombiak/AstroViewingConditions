# Astronomer Grok skill release notes

This is the repository source for the first private/shared Astronomer skill. Grok
discovers the folder directly from `.grok/skills` in a checkout. The desired
product path is for a recipient to add the shared Astronomer Bot and ask an
astronomy question, with the complete enabled skill available to bootstrap the
runtime automatically.

Whether Bot sharing materializes the complete private-skill artifact (including
this manifest, scripts, and references) in the recipient environment is not yet
proven by this project. Fresh-user Grok acceptance must test that path first. Do
not claim either that a separate manual skill install is required or that
zero-touch transport is already verified. If sharing does not transport the
artifact, record the result and decide separately whether plugin/Marketplace
packaging is needed.

The skill is intentionally not a Marketplace plugin. Its Python bootstrap uses
only the standard library. It installs released wheels into a user-owned,
versioned virtual environment and keeps host state in a sibling `state` directory.

Before distributing a release:

1. Build the two wheels with `tools/grok/build_runtime_release.py` and take the
   SHA-256 values from its `release-artifacts.json` output.
2. Update or verify each artifact's filename, URL, and SHA-256 value in
   `runtime-manifest.json` against that builder output.
3. Run the local wheel smoke and bootstrap tests.
4. Upload exactly the verified wheel files to the GitHub release named in the
   manifest.
5. Test first-use bootstrap through Astronomer on a fresh Grok computer.

Never publish a manifest with pending hashes. The bootstrap rejects it clearly.
