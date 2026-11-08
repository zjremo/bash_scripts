#!/usr/bin/env bash

get_github_resMsg () {
    base_url=https://api.github.com/search/repositories
    q=react
    sort=stars
    order=desc

    while read line; do
        echo $line >> "data/github_res.txt"
    done< <(
    curl -G $base_url \
        -d "q=$q" \
        -d "sort=$sort" \
        -d "order=$order"
    )
}

get_jsonPlaceHolder_msg() {
    # 获取所有文章 -i 开发使用，显示详细信息
    curl -i https://jsonplaceholder.typicode.com/posts

    # Query Params usage 
    curl -s -G "https://jsonplaceholder.typicode.com/posts" \
        -d "userId=1"

    # POST Method + Request Body + Requeet Header
    curl -X POST https://jsonplaceholder.typicode.com/posts \
        -H "Content-Type: application/json" \
        -d '{
        "title": "updated",
        "body": "new content",
        "userId": 1
    }'

    # POST Method + test_req.json + test_resp.json
    # 指定从文件获取json请求体，加载响应体到文件
    curl -X POST https://jsonplaceholder.typicode.com/posts \
        -H "Content-Type: application/json" \
        -d @data/test_req.json \
        -o data/test_resp.json
}

get_github_resMsg
get_jsonPlaceHolder_msg
