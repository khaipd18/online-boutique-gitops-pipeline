// Shared layout for the project manuals (Technical Design Document, Operations Runbook).
// Each document calls `manual.with(...)` once; English and Vietnamese editions share this file
// so they always look the same.

#let palette = (
  ink: rgb("#1f2933"),
  muted: rgb("#52606d"),
  accent: rgb("#0b5cad"),
  accent-soft: rgb("#e8f1fb"),
  rule: rgb("#cbd2d9"),
  stripe: rgb("#f5f7fa"),
  note: rgb("#0b5cad"),
  warn: rgb("#b7791f"),
  danger: rgb("#c53030"),
  ok: rgb("#2f855a"),
)

#let strings = (
  en: (
    contents: "Contents",
    doc-control: "Document control",
    field: "Field",
    value: "Value",
    doc-id: "Document ID",
    version: "Version",
    date: "Date",
    status: "Status",
    owner: "Owner",
    audience: "Audience",
    classification: "Classification",
    repository: "Repository",
    revisions: "Revision history",
    change: "Change",
    author: "Author",
    related: "Related documents",
    page: "Page",
    of: "of",
    note: "Note",
    warning: "Warning",
    important: "Important",
    tip: "Tip",
  ),
  vi: (
    contents: "Mục lục",
    doc-control: "Kiểm soát tài liệu",
    field: "Mục",
    value: "Giá trị",
    doc-id: "Mã tài liệu",
    version: "Phiên bản",
    date: "Ngày",
    status: "Trạng thái",
    owner: "Người phụ trách",
    audience: "Đối tượng đọc",
    classification: "Phân loại",
    repository: "Repository",
    revisions: "Lịch sử thay đổi",
    change: "Thay đổi",
    author: "Người thực hiện",
    related: "Tài liệu liên quan",
    page: "Trang",
    of: "/",
    note: "Ghi chú",
    warning: "Cảnh báo",
    important: "Quan trọng",
    tip: "Mẹo",
  ),
)

// Callout boxes used for notes, warnings and important steps
#let callout(kind, lang: "en", body) = {
  let (color, key) = (
    note: (palette.note, "note"),
    tip: (palette.ok, "tip"),
    warning: (palette.warn, "warning"),
    important: (palette.danger, "important"),
  ).at(kind)
  block(
    width: 100%,
    inset: (left: 10pt, right: 10pt, top: 7pt, bottom: 7pt),
    fill: color.lighten(92%),
    stroke: (left: 3pt + color),
    radius: (right: 2pt),
    breakable: true,
  )[
    #text(weight: "bold", fill: color, size: 8.5pt)[#upper(strings.at(lang).at(key))]
    #v(-4pt)
    #body
  ]
}

// Incident playbook: symptom, cause, diagnosis, fix as a key/value table kept on one page
#let playbook(labels, symptom: [], cause: [], diagnose: [], fix: []) = block(breakable: false, {
  show table.cell.where(y: 0): set text(fill: palette.ink, weight: "regular", size: 8.8pt)
  show table.cell.where(x: 0): set text(weight: "bold")
  table(
    columns: (18%, 1fr),
    fill: (x, _) => if x == 0 { palette.stripe } else { none },
    labels.at(0), symptom,
    labels.at(1), cause,
    labels.at(2), diagnose,
    labels.at(3), fix,
  )
})

// Compact key/value table
#let kv(..rows) = table(
  columns: (32%, 1fr),
  ..rows.pos().flatten(),
)

#let manual(
  title: "",
  subtitle: "",
  doc-id: "",
  version: "1.0",
  date: "",
  status: "",
  owner: "",
  audience: "",
  classification: "",
  repository: "",
  revisions: (),
  related: (),
  lang: "en",
  body,
) = {
  let s = strings.at(lang)

  set document(title: title, author: owner)
  set text(font: "Noto Sans", size: 10pt, fill: palette.ink, lang: lang, hyphenate: false)
  set par(justify: true, leading: 0.68em, spacing: 1.05em)
  show raw: set text(font: "Noto Sans Mono", size: 8.6pt)
  show link: set text(fill: palette.accent)

  set heading(numbering: "1.1")
  show heading: set text(fill: palette.ink)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(4pt)
    block(below: 14pt)[
      #text(size: 17pt, weight: "bold", fill: palette.accent)[
        #if it.numbering != none [#counter(heading).display(it.numbering)#h(10pt)]#it.body
      ]
      #v(-6pt)
      #line(length: 100%, stroke: 0.8pt + palette.accent)
    ]
  }
  show heading.where(level: 2): set text(size: 12.5pt)
  show heading.where(level: 2): set block(above: 18pt, below: 9pt)
  show heading.where(level: 3): set text(size: 10.5pt)
  show heading.where(level: 3): set block(above: 14pt, below: 8pt)

  // Code blocks: shaded, never split a short block across pages
  show raw.where(block: true): it => block(
    width: 100%,
    fill: palette.stripe,
    stroke: 0.5pt + palette.rule,
    radius: 2pt,
    inset: 8pt,
    breakable: true,
    it,
  )

  // Tables: header row in accent colour, light zebra stripes
  set table(
    stroke: 0.5pt + palette.rule,
    inset: (x: 6pt, y: 5pt),
    fill: (_, y) => if y == 0 { palette.accent } else if calc.even(y) { palette.stripe } else { none },
    align: left + horizon,
  )
  show table.cell.where(y: 0): set text(fill: white, weight: "bold", size: 8.8pt)
  show table: set text(size: 8.8pt)
  // Let long identifiers in table cells wrap after / . - _ instead of overflowing the column
  show table: it => {
    show raw.where(block: false): r => text(
      font: "Noto Sans Mono",
      size: 8.2pt,
      r.text.replace("/", "/\u{200B}").replace(".", ".\u{200B}").replace("-", "-\u{200B}").replace("_", "_\u{200B}"),
    )
    it
  }
  show table: set par(justify: false)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.caption: set text(size: 8.8pt, fill: palette.muted)
  set figure(gap: 8pt)

  set list(indent: 4pt, body-indent: 6pt)
  set enum(indent: 4pt, body-indent: 6pt)

  // ---------------------------------------------------------------- cover page
  page(margin: 0cm, header: none, footer: none)[
    #block(width: 100%, height: 7.2cm, fill: palette.accent, inset: (x: 2.2cm, top: 2.4cm))[
      #set text(fill: white)
      #text(size: 10pt, tracking: 1.5pt, weight: "bold")[ONLINE BOUTIQUE ON AMAZON EKS]
      #v(10pt)
      #text(size: 26pt, weight: "bold")[#title]
      #v(2pt)
      #text(size: 13pt)[#subtitle]
    ]
    #place(bottom + left, dx: 2.2cm, dy: -1.4cm, text(size: 8pt, fill: palette.muted)[#doc-id · v#version · #date])
    #v(1.6cm)
    #show: pad.with(x: 2.2cm)
    #set table(fill: (x, _) => if x == 0 { palette.stripe } else { none })
    #show table.cell.where(y: 0): set text(fill: palette.ink, weight: "regular", size: 9.5pt)
    #show table.cell.where(x: 0): set text(weight: "bold")
    #set text(size: 9.5pt)
    #table(
      columns: (30%, 1fr),
      inset: (x: 8pt, y: 7pt),
      [#s.doc-id], [#doc-id],
      [#s.version], [#version],
      [#s.date], [#date],
      [#s.status], [#status],
      [#s.owner], [#owner],
      [#s.audience], [#audience],
      [#s.classification], [#classification],
      [#s.repository], [#link(repository)],
    )
  ]

  // ------------------------------------------------- header, footer, page numbers
  set page(
    paper: "a4",
    margin: (x: 2.2cm, top: 2.4cm, bottom: 2.2cm),
    header: context {
      set text(size: 8pt, fill: palette.muted)
      grid(columns: (1fr, auto), title, doc-id)
      v(-4pt)
      line(length: 100%, stroke: 0.4pt + palette.rule)
    },
    footer: context {
      set text(size: 8pt, fill: palette.muted)
      line(length: 100%, stroke: 0.4pt + palette.rule)
      v(-4pt)
      grid(
        columns: (1fr, auto, 1fr),
        align(left)[#s.version #version · #date],
        align(center)[#classification],
        align(right)[#s.page #counter(page).display() #s.of #counter(page).final().first()],
      )
    },
  )
  counter(page).update(1)

  // -------------------------------------------------------- document control
  heading(level: 1, numbering: none, outlined: false, s.doc-control)
  heading(level: 2, numbering: none, outlined: false, s.revisions)
  table(
    columns: (auto, auto, 1fr, auto),
    [#s.version], [#s.date], [#s.change], [#s.author],
    ..revisions.flatten(),
  )
  if related.len() > 0 {
    heading(level: 2, numbering: none, outlined: false, s.related)
    for r in related [- #r]
  }
  v(14pt)
  outline(title: s.contents, depth: 2, indent: auto)

  body
}
