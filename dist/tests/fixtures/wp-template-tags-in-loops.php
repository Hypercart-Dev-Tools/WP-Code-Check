<?php
/**
 * Test Fixture: WordPress Template Tags in Loops (N+1 Patterns)
 * 
 * This file contains examples of WordPress template tag N+1 patterns
 * that should be detected by the wp-template-tags-in-loops pattern.
 * 
 * Expected violations: 6
 */

// ============================================================
// VIOLATIONS - These should be detected
// ============================================================

// VIOLATION 1: get_the_title() with post ID in loop
function display_post_titles_bad($post_ids) {
    foreach ($post_ids as $post_id) {
        $title = get_the_title($post_id); // N+1: Separate query per post
        echo "<h2>$title</h2>";
    }
}

// VIOLATION 2: Multiple template tags in loop
function display_post_cards_bad($post_ids) {
    foreach ($post_ids as $post_id) {
        $title = get_the_title($post_id);       // N+1
        $link = get_permalink($post_id);        // N+1
        $excerpt = get_the_excerpt($post_id);   // N+1
        echo "<a href='$link'><h3>$title</h3><p>$excerpt</p></a>";
    }
}

// VIOLATION 3: get_the_content() in loop
function export_post_content_bad($post_ids) {
    $content_array = array();
    foreach ($post_ids as $id) {
        $content_array[] = get_the_content(null, false, $id); // N+1
    }
    return $content_array;
}

// VIOLATION 4: get_the_author() and get_the_date() in loop
function display_post_meta_bad($post_ids) {
    foreach ($post_ids as $post_id) {
        $author = get_the_author_meta('display_name', get_post_field('post_author', $post_id)); // N+1
        $date = get_the_date('Y-m-d', $post_id); // N+1
        echo "By $author on $date";
    }
}

// VIOLATION 5: get_post_thumbnail_url() in loop
function get_featured_images_bad($post_ids) {
    $images = array();
    foreach ($post_ids as $post_id) {
        $images[] = get_the_post_thumbnail_url($post_id, 'large'); // N+1
    }
    return $images;
}

// VIOLATION 6: get_post() in loop (fetches full post object)
function get_post_data_bad($post_ids) {
    foreach ($post_ids as $post_id) {
        $post = get_post($post_id); // N+1: Fetches post object
        echo $post->post_title;
    }
}

// ============================================================
// VALID CODE - These should NOT be detected
// ============================================================

// VALID 1: Using WP_Query with proper setup_postdata()
function display_posts_good_wpquery($post_ids) {
    $query = new WP_Query(array(
        'post__in' => $post_ids,
        'posts_per_page' => count($post_ids),
    ));
    
    while ($query->have_posts()) {
        $query->the_post();
        $title = get_the_title();    // ✅ Uses global $post, no query
        $link = get_permalink();     // ✅ Uses global $post, no query
        echo "<a href='$link'>$title</a>";
    }
    
    wp_reset_postdata();
}

// VALID 2: Using get_posts() with setup_postdata()
function display_posts_good_get_posts($post_ids) {
    $posts = get_posts(array(
        'include' => $post_ids,
        'posts_per_page' => count($post_ids),
    ));
    
    foreach ($posts as $post) {
        setup_postdata($post); // ✅ Sets global $post
        $title = get_the_title();
        $excerpt = get_the_excerpt();
        echo "<h3>$title</h3><p>$excerpt</p>";
    }
    
    wp_reset_postdata();
}

// VALID 3: Accessing post object properties directly (no template tags)
function display_posts_good_direct_access($post_ids) {
    $posts = get_posts(array(
        'include' => $post_ids,
        'posts_per_page' => count($post_ids),
    ));
    
    foreach ($posts as $post) {
        echo $post->post_title;    // ✅ Direct property access, no query
        echo $post->post_excerpt;  // ✅ Direct property access, no query
    }
}

// VALID 4: Template tags without parameters (within The Loop)
function display_current_post_good() {
    // Assumes this is called within The Loop where global $post is set
    $title = get_the_title();      // ✅ No parameter, uses global $post
    $content = get_the_content();  // ✅ No parameter, uses global $post
    echo "<h1>$title</h1><div>$content</div>";
}

// VALID 5: Single template tag call (not in a loop)
function get_single_post_title_good($post_id) {
    return get_the_title($post_id); // ✅ Not in a loop, not N+1
}

// VALID 6: Pre-fetching with custom query
function display_posts_good_custom_query($category_id) {
    $posts = get_posts(array(
        'category' => $category_id,
        'posts_per_page' => 10,
    ));
    
    foreach ($posts as $post) {
        // ✅ All data already loaded, no additional queries
        echo $post->post_title;
        echo $post->post_date;
    }
}

