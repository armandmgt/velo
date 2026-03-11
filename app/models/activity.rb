class Activity < ApplicationRecord
  belongs_to :user

  enum :sport, %i[
    bike
    run
  ].index_by(&:itself)
end
