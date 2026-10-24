class RecordsController < ApplicationController
  def index
    category = PersonalRecords::CATEGORIES.find { |c| c.to_s == params[:category] } || PersonalRecords::CATEGORIES.first
    @records = PersonalRecords.new(Current.user, category:)
    @years   = @records.years
    year     = params[:year].to_i
    @records = PersonalRecords.new(Current.user, category:, year:) if @years.include?(year)
  end
end
