include "contract";
validate_manifest | . as $manifest |
{schema:1, manifest_id:$manifest.id, suite:$manifest.suite, samples:planned}
