import Chart from "chart.js"
import { BRAND, FILL } from "~/javascript/charts/colors"

export default function(selector, labels, values, scale) {
  var ctx = document.querySelector(selector)
                    .getContext('2d');

  new Chart(ctx, {
    type: "line",
    data: {
      labels: labels,
      datasets: [
        {
          data: values,
          fill: true,
          lineTension: 0.2,
          borderWidth: 5,
          pointRadius: 1,
          backgroundColor: FILL,
          borderColor: BRAND
        }
      ]
    },
    options: {
      animation: false,
      legend: {
        display: false
      },
      tooltips: {
        mode: "index",
        intersect: false,
        axis: "x"
      },
      scales: {
        xAxes: [
          {
            gridLines : {
              display : false
            }
          }
        ],
        yAxes: [
          {
            type: scale,
            ticks: {
              beginAtZero: true,
              callback: function(value, index) {
                if (index % 8 == 0) { return value; }
              }
            }
          }
        ]
      }
    }
  });
}
