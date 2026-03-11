class Activity < ApplicationRecord
  belongs_to :user

  enum :sport, %i[
    bike
    run
  ].index_by(&:itself)

  validates :name, :sport, presence: true
end
