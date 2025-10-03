const path = require('path')
const HtmlWebPackPlugin = require("html-webpack-plugin")

module.exports = {

    module: {
        rules: [
            {
                test: /.(js)$/,
                exclude: /node_modules/,
                use: ['babel-loader']
            },
            {
                test: /\.css$/,
                use: [
                    'style-loader',
                    'css-loader'
                ]
            },
            {
                test: /\.scss$|\.sass$/,
                use: [
                    'style-loader',
                    'css-loader',
                    'sass-loader'
                ]
            },
            {
                test: /\.(png|jpg|gif|mp4|ogg|svg|woff|woff2|ttf|eot)$/,
                loader: 'file-loader'
            },
        ]
    },

    plugins: [
        new HtmlWebPackPlugin({
            template: path.resolve(__dirname, 'index.template.html'),
            filename: "../index.html"
        })
    ]

}