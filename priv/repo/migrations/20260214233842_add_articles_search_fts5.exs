defmodule Icarurss.Repo.Migrations.AddArticlesSearchFts5 do
  use Ecto.Migration

  def up do
    execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS articles_search USING fts5(
      title,
      content,
      feed_title,
      feed_site_url,
      feed_base_url,
      user_id UNINDEXED,
      tokenize = 'unicode61 remove_diacritics 2'
    );
    """)

    execute("""
    INSERT INTO articles_search (
      rowid,
      title,
      content,
      feed_title,
      feed_site_url,
      feed_base_url,
      user_id
    )
    SELECT
      articles.id,
      coalesce(articles.title, ''),
      trim(coalesce(articles.content_html, '') || ' ' || coalesce(articles.summary_html, '')),
      coalesce(feeds.title, ''),
      coalesce(feeds.site_url, ''),
      coalesce(feeds.base_url, ''),
      articles.user_id
    FROM articles
    JOIN feeds ON feeds.id = articles.feed_id;
    """)

    execute("""
    CREATE TRIGGER articles_search_ai
    AFTER INSERT ON articles
    BEGIN
      INSERT INTO articles_search (
        rowid,
        title,
        content,
        feed_title,
        feed_site_url,
        feed_base_url,
        user_id
      )
      VALUES (
        new.id,
        coalesce(new.title, ''),
        trim(coalesce(new.content_html, '') || ' ' || coalesce(new.summary_html, '')),
        coalesce((SELECT title FROM feeds WHERE id = new.feed_id), ''),
        coalesce((SELECT site_url FROM feeds WHERE id = new.feed_id), ''),
        coalesce((SELECT base_url FROM feeds WHERE id = new.feed_id), ''),
        new.user_id
      );
    END;
    """)

    execute("""
    CREATE TRIGGER articles_search_au
    AFTER UPDATE ON articles
    BEGIN
      DELETE FROM articles_search WHERE rowid = old.id;
      INSERT INTO articles_search (
        rowid,
        title,
        content,
        feed_title,
        feed_site_url,
        feed_base_url,
        user_id
      )
      VALUES (
        new.id,
        coalesce(new.title, ''),
        trim(coalesce(new.content_html, '') || ' ' || coalesce(new.summary_html, '')),
        coalesce((SELECT title FROM feeds WHERE id = new.feed_id), ''),
        coalesce((SELECT site_url FROM feeds WHERE id = new.feed_id), ''),
        coalesce((SELECT base_url FROM feeds WHERE id = new.feed_id), ''),
        new.user_id
      );
    END;
    """)

    execute("""
    CREATE TRIGGER articles_search_ad
    AFTER DELETE ON articles
    BEGIN
      DELETE FROM articles_search WHERE rowid = old.id;
    END;
    """)

    execute("""
    CREATE TRIGGER articles_search_feed_au
    AFTER UPDATE OF title, site_url, base_url ON feeds
    BEGIN
      UPDATE articles_search
      SET
        feed_title = coalesce(new.title, ''),
        feed_site_url = coalesce(new.site_url, ''),
        feed_base_url = coalesce(new.base_url, '')
      WHERE rowid IN (SELECT id FROM articles WHERE feed_id = new.id);
    END;
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS articles_search_feed_au;")
    execute("DROP TRIGGER IF EXISTS articles_search_ad;")
    execute("DROP TRIGGER IF EXISTS articles_search_au;")
    execute("DROP TRIGGER IF EXISTS articles_search_ai;")
    execute("DROP TABLE IF EXISTS articles_search;")
  end
end
