# A correct T1 fix: reject instead of answering 200.
import pathlib, sys
r = pathlib.Path(sys.argv[1])
p = r / 'src/invoices/invoices.controller.ts'
s = p.read_text()
s = s.replace("import { Body, Controller, Get, HttpCode, Post, Query, UseGuards }",
              "import { BadRequestException, Body, Controller, Get, HttpCode, Post, Query, UseGuards }")
s = s.replace("      return { ok: false, errors };", "      throw new BadRequestException(errors);")
p.write_text(s)
