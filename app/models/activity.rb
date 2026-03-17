class Activity < ApplicationRecord
  belongs_to :user

  has_one_attached :fit_file

  enum :sport, %i[
    bike
    run
  ].index_by(&:itself)

  validates :name, :sport, :start_time, :end_time, :location, :active_time, presence: true

  def parse_fit_file(fit_file)
    RubyFit::Parser.new(FitExtractor.new(self)).parse(fit_file.open)
  end

  def active_time_duration
    ActiveSupport::Duration.parse(active_time)
  end

  def duration
    ActiveSupport::Duration.build((end_time - start_time).to_i)
  end
end
