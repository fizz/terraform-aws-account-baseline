# Conformance pack templates

Unmodified copies of AWS's published sample templates from
https://github.com/awslabs/aws-config-rules/tree/master/aws-config-conformance-packs,
licensed under the Apache License 2.0. They are bundled so a plan never depends on a
download.

| File | Used when |
|---|---|
| `Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml` | `enable_cis_pack = true` |
| `Operational-Best-Practices-for-HIPAA-Security.yaml` | `enable_hipaa_pack = true` |

Config accepts at most 51,200 bytes of inline template. The HIPAA file is 50,485
bytes, so a newer upstream version can exceed the limit. Check the size before you
replace it. If it is over, upload it to a bucket named `awsconfigconforms*` and switch
the resource to `template_s3_uri`.
