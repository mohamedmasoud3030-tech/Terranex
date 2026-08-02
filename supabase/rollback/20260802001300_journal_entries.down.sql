drop function if exists void_journal_entry(text, uuid);
drop function if exists post_journal_entry(text, uuid);
drop table if exists journal_entry_lines cascade;
drop table if exists journal_entries cascade;
