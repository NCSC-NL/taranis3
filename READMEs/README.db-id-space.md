# PostgreSQL IDs 

As usual for databases, most tables contain a sequence id.   Be default, they
all count from 1. In Taranis, we give each table a separate range.  Sequences
are 64 bits, so there is enough number space to give each their own billion.

In Taranis, some tables are quite complex referencing via ids from a single
column to different tables.  Also, it adds power to the constraint checking.

Old installations may still use ids which all start at "1".  You may load
an older dataset in a new database schema, so we cannot enforce a minimal
value.

## Allocation

To avoid the need to count digits in (for instance) 100000000 (is this
'1'-billion or '10'-billion?), we will not assign the latter range.

Do not reuse ranges were freed: the number space is large enough.

## Allocated

```
  00000000 -- not used for new installations
  10000000 advisory\_linked\_items\_id\_seq
  20000000 calling\_list\_id\_seq
  30000000 category\_id\_seq
  40000000 cluster\_id\_seq
  50000000 collector\_id\_seq
  60000000 constituent\_group\_id\_seq
  70000000 constituent\_individual\_id\_seq
  80000000 constituent\_publication\_id\_seq
  90000000 constituent\_role\_id\_seq
 100000000 -- not used
 110000000 constituent\_type\_id\_seq
 120000000 damage\_description\_id\_seq
 130000000 email\_item\_id\_seq
 140000000 entitlement\_id\_seq
 150000000 errors\_id\_seq
 160000000 import\_issue\_id\_seq
 170000000 import\_photo\_id\_seq
 180000000 import\_software\_hardware\_id\_seq
 190000000 item\_id\_seq
 200000000 -- not used
 210000000 membership\_id\_seq
 220000000 phish\_id\_seq
 230000000 publication\_id\_seq
 240000000 publication2constituent\_id\_seq
 250000000 publication\_advisory\_id\_seq
 260000000 publication\_advisory\_forward\_id\_seq
 260000000 publication\_attachment\_id\_seq
 270000000 publication\_endofday\_id\_seq
 280000000 publication\_endofweek\_id\_seq
 290000000 publication\_template\_id\_seq
 300000000 -- not used
 310000000 publication\_type\_id\_seq
 320000000 role\_id\_seq
 330000000 role\_right\_id\_seq
 340000000 search\_id\_seq
 350000000 soft\_hard\_usage\_id\_seq
 360000000 software\_hardware\_id\_seq
 370000000 software\_hardware\_cpe\_import\_id\_seq
 380000000 sources\_id\_seq
 390000000 statistics\_analyze\_id\_seq
 400000000 -- not used
 410000000 statistics\_assess\_id\_seq
 420000000 statistics\_collector\_id\_seq
 430000000 statistics\_database\_id\_seq
 440000000 tag\_id\_seq
 450000000 user\_action\_id\_seq
 460000000 user\_role\_id\_seq
 470000000 dossier\_id\_seq
 480000000 dossier\_note\_id\_seq
 490000000 dossier\_note\_url\_id\_seq
 500000000 -- not used
 510000000 dossier\_note\_ticket\_id\_seq
 520000000 dossier\_note\_file\_id\_seq
 530000000 dossier\_item\_id\_seq
 540000000 wordlist\_id\_seq
 550000000 source\_wordlist\_id\_seq
 560000000 feeddigest\_id\_seq
 570000000 cve\_template\_id\_seq
 580000000 report\_todo\_id\_seq
 590000000 report\_special\_interest\_id\_seq
 600000000 -- not used
 610000000 report\_contact\_log\_id\_seq
 620000000 report\_incident\_log\_id\_seq
 630000000 publication\_endofshift\_id\_seq
 640000000 stream\_id\_seq
 650000000 announcement\_id\_seq
```