class Activity < ApplicationRecord
  belongs_to :user

  enum :sport, %i[
    bike
    run
  ]
end
