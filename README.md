READ FIRST!!!
=============

DO NOT USE THIS UTILITY -> Better way explained below.

Since writing this utility I've learned more about Linux piping.

Do this is as simple as running something like this:
tar czf - <files> | ssh user@host "cd /wherever; tar xvzf -"


Copy NFS: utility to copy large amounts of files quickly over NFS
