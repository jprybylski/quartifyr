-- Defaults `csl:` and `link-citations:` whenever a project sets
-- `bibliography:` but doesn't pick its own -- so citations/references come
-- out in a style regulated/scientific reports actually use, out of the
-- box, rather than pandoc's own defaults (Chicago author-date, and
-- in-text citations that aren't linked to their bibliography entry). A
-- project can still override either with its own `csl:`/`link-citations:`
-- in the shell .qmd's frontmatter; this filter only fills gaps that
-- aren't set at all.
--
-- `nlm.csl` is NLM/Vancouver: Citing Medicine 2nd edition
-- (citation-sequence, brackets -- `[1]`, `[2]`, ... in order of
-- appearance), from the official CSL styles repository
-- (https://github.com/citation-style-language/styles), CC-BY-SA -- see
-- its own <rights> element.
--
-- The path below is relative to the *project* root, not this file --
-- that's how Quarto/pandoc resolves a `csl:` value regardless of which
-- extension set it, confirmed empirically (a path relative to this
-- extension's own directory does not resolve).
return {
  {
    Meta = function(meta)
      if meta.csl == nil then
        meta.csl = "_extensions/quartifyr/nlm.csl"
      end
      if meta["link-citations"] == nil then
        meta["link-citations"] = true
      end
      return meta
    end,
  },
}
