# The attachment has always also held GPX, so `fit_file` misled — it is why
# code sniffed filenames to work out what it was holding. See CONTEXT.md
# (Source file) and docs/adr/0005-fit-file-param-is-an-accepted-alias.md, which
# covers why the *upload parameter* keeps the old name even though this doesn't.
#
# Lives in db/migrate rather than db/data deliberately: it has to run in the same
# breath as the code that declares `has_one_attached :source_file`, and deploys
# run `db:prepare` (schema migrations only — see bin/docker-entrypoint), so a
# data migration would leave every existing Source file unreachable until someone
# ran it by hand.
class RenameFitFileAttachmentsToSourceFile < ActiveRecord::Migration[8.1]
  def up
    rename_attachments(from: "fit_file", to: "source_file")
  end

  def down
    rename_attachments(from: "source_file", to: "fit_file")
  end

  private

  def rename_attachments(from:, to:)
    renamed = ActiveStorage::Attachment
                .where(record_type: "Activity", name: from)
                .update_all(name: to)

    say "Renamed #{renamed} Activity attachment(s): #{from} -> #{to}"
  end
end
