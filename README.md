# Velo

Velo is a free, open-source alternative to Strava, built for athletes who want to track their progress, compete on segments, and stay connected with their community without a subscription.

## Features

- **Activity Tracking**: Upload and visualize your GPS activities (cycling, running, etc.).
- **Segment Records**: Compete for the fastest times on popular segments.
- **Social Features**: Follow friends, like and comment on activities, and share your achievements.
- **Open Source**: Your data belongs to you, and the platform is built by the community.

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/velo.git
   cd velo
   ```

2. **Install dependencies**:
   ```bash
   bundle install
   ```

3. **Set up the database**:
   ```bash
   bin/rails db:prepare
   ```

4. **Start the development server**:
   ```bash
   bin/dev
   ```

Velo will be available at `http://localhost:3000`.

## Testing

Run the test suite to ensure everything is working correctly:

```bash
bin/rails test
```

For system tests:

```bash
bin/rails test:system
```

## Tech Stack

- **Framework**: [Ruby on Rails 8.1](https://rubyonrails.org/)
- **Frontend**: [Hotwire](https://hotwired.dev/) (Turbo & Stimulus), [Tailwind CSS](https://tailwindcss.com/)
- **Database**: [SQLite](https://www.sqlite.org/)
- **Caching & Background Jobs**: [Solid Cache](https://github.com/rails/solid_cache), [Solid Queue](https://github.com/rails/solid_queue)
- **Deployment**: [Kamal](https://kamal-deploy.org/)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Velo is released under the [MIT License](https://opensource.org/licenses/MIT).
